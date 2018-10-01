pragma solidity ^0.4.24;

import "./Z_ERC20.sol";
import "./SafeMath.sol";

contract DutchAuction {
    using SafeMath for uint256;
    // Auction Bid
    struct Bid {
        uint256 price;
        uint256 value;
        bool placed;
        bool claimed;
        bool absentee;
        bool useWholeAmount;
        uint256 numOfToken;
        address sender;
    }

    // Auction Stages
    enum Stages {
        AuctionDeployed,
        AuctionStarted,
        AuctionEnded,
        TokensDistributed
    }

    // Auction Ending Reasons
    enum Endings {
        Manual,
        ReservePriceReached,
        SoldOut
    }

    // Auction Events
    event AuctionDeployed(uint256 indexed priceStart);
    event AuctionStarted(uint256 _startTime);
    event AuctionEnded(uint256 priceFinal, uint256 _endTime, Endings ending);
    event BidAccepted(address indexed _address, uint256 price, uint256 transfer);
    event BidPartiallyRefunded(address indexed _address, uint256 transfer);
    event BidRefunded(address indexed _address, uint256 transfer);
    event FundsTransfered(address indexed _bidder, address indexed _wallet, uint256 amount);
    event TokensClaimed(address indexed _address, uint256 amount);
    event TokensDistributed();

    bool public saleOn = true;

    //intervals
    uint256 public intervals_duration;

    // Token contract reference
    ERC20 public token;

    // Current stage
    Stages public current_stage;

    struct PricePreBidder {
        bytes32[] bidHashes;
        bool exist;
    }

    // price mapping to addresses of pre bidders
    mapping(uint256 => PricePreBidder) public preBidders;

    // `bytes32 unique bid id` ⇒ `Bid` mapping
    mapping(bytes32 => Bid) public bids;

    // address to bid hash mapping
    mapping(address => bytes32[]) senderBidHash;

    struct Refund {
        uint256 amount;
        bool refunded;
    }

    //
    mapping(address => Refund) public refunds;

    Bid[] public bidSeq;

    // Auction owner address
    address public owner_address;

    // Wallet address
    address public wallet_address;

    // Starting price in wei
    uint256 public price_start;

    //Reserve price in wei
    uint256 public price_reserve;

    // Current price in wei
    uint256 public price_current;

    // Final price in wei
    uint256 public price_final;

    // Number of received wei
    uint256 public received_wei = 0;

    // Number of claimed wei
    uint256 public claimed_wei = 0;

    // Total number of token units for auction
    uint256 public initial_offering;

    // Auction start time
    uint256 public start_time;

    // Interval start time
    uint256 public interval_start_time;

    // Auction end time
    uint256 public end_time;

    // Time after the end of the auction, before anyone can claim tokens
    uint256 public claim_period;

    // Minimum bid amount
    uint256 public minimum_bid;

    //Total tokens bidded in the case when bidder want only a fixed number of tokens
    uint256 public tokens_in_bid;

    //Total amount in bid when bidder wants whole amount to invest
    uint256 public amount_in_bid;

    uint256 public price_change;

    // Stage modifier
    modifier atStage(Stages _stage) {
        require(current_stage == _stage);
        _;
    }

    modifier atStageOr(Stages _stage1, Stages _stage2) {
        require(current_stage == _stage1 || current_stage == _stage2);
        _;
    }

    // Owner modifier
    modifier isOwner() {
        require(msg.sender == owner_address);
        _;
    }

    modifier isSaleOn() {
        require(saleOn == true);
        _;
    }

    constructor(
        uint256 _priceStart,
        uint256 _priceReserve,
        uint256 _priceChange,
        uint256 _minimumBid,
        uint256 _claimPeriod,
        address _walletAddress,
        uint256 _intervalDuration,
        uint256 _offering,
        address _tokenAddress,
        address _ownerAddress
    ) public {

        // Set auction owner address
        owner_address = _ownerAddress;
        wallet_address = _walletAddress;

        // // Initialize external contract type
        token = ERC20(_tokenAddress);
        uint256 balance = token.balanceOf(owner_address);

        // Verify & Initialize starting parameters
        require(balance >= _offering);
        // TODO check spending limit of contract
        initial_offering = _offering;

        // Set auction parameters
        price_start = _priceStart;
        price_reserve = _priceReserve;
        price_change = _priceChange;
        price_current = _priceStart;
        minimum_bid = _minimumBid;
        claim_period = _claimPeriod;
        intervals_duration = _intervalDuration;

        // Update auction stage and fire event
        current_stage = Stages.AuctionDeployed;
        emit AuctionDeployed(_priceStart);
    }

    function toggleSaleOn() public isOwner {
        saleOn = !saleOn;
    }

    // Absentee Bid Interface
    function absenteeBid(uint256 _price, uint256 _numOfToken, bool _useWholeAmount) public payable isSaleOn atStage(Stages.AuctionDeployed) {

        address sender = msg.sender;
        uint256 bidValue = msg.value;

        if (_useWholeAmount) {
            require(_numOfToken == 0);
        } else {
            require(_numOfToken == bidValue.div(_price));
        }

        bytes32 bidHash = calculateBidHash(sender, _price, _numOfToken, _useWholeAmount);

        require(!bids[bidHash].absentee && _price >= price_reserve && bidValue >= minimum_bid);
        require(price_start.sub(_price) % price_change == 0);

        // Create bid
        Bid memory bid = Bid({
            price : _price,
            value : bidValue,
            placed : false,
            claimed : false,
            absentee : true,
            useWholeAmount : _useWholeAmount,
            numOfToken : _numOfToken,
            sender : sender
            });

        bids[bidHash] = bid;
        senderBidHash[sender].push(bidHash);

        preBidders[_price].exist = true;
        preBidders[_price].bidHashes.push(bidHash);

        received_wei = received_wei.add(bidValue);

        //wallet_address.transfer(bidValue);

        //emit FundsTransfered(sender, wallet_address, bidValue);
    }

    function doBid(uint256 _price, uint256 _numOfToken, bool _useWholeAmount) public payable isSaleOn atStage(Stages.AuctionStarted) {

        address sender = msg.sender;
        uint256 bidValue = msg.value;

        bytes32 bidHash = calculateBidHash(sender, _price, _numOfToken, _useWholeAmount);

        require(!bids[bidHash].placed && _price == price_current && bidValue >= minimum_bid);

        if (_useWholeAmount) {
            require(_numOfToken == 0);
        } else {
            require(_numOfToken == bidValue.div(_price));
        }

        uint256 acceptableTokens = initial_offering.sub(tokens_in_bid.add(amount_in_bid.div(price_current)));

        if (acceptableTokens <= 0) {
            endImmediately(price_current, Endings.SoldOut);
        }

        uint256 askedTokens = _useWholeAmount ? bidValue.div(price_current) : _numOfToken;

        if (askedTokens > acceptableTokens) {

            uint256 returnedWei = (askedTokens.sub(acceptableTokens)).mul(price_current);

            // Place bid with available value
            placeBidInner(sender, price_current, bidValue.sub(returnedWei), _useWholeAmount, acceptableTokens);

            // Refund remaining value
            sender.transfer(returnedWei);
            emit BidPartiallyRefunded(sender, returnedWei);

            // End auction
            endImmediately(price_current, Endings.SoldOut);
        } else if (askedTokens == acceptableTokens) {
            // Place last bid && end auction
            placeBidInner(sender, price_current, bidValue, _useWholeAmount, askedTokens);
            endImmediately(price_current, Endings.SoldOut);
        } else {
            // Place bid and update last price
            placeBidInner(sender, price_current, bidValue, _useWholeAmount, askedTokens);
        }
    }

    // Inner function for placing bid
    function placeBidInner(address sender, uint256 price, uint256 value, bool useWholeAmount, uint256 numOfToken) private atStage(Stages.AuctionStarted) {
        // Create bid
        Bid memory bid = Bid({
            price : price,
            value : value,
            placed : true,
            claimed : false,
            absentee : false,
            useWholeAmount : useWholeAmount,
            numOfToken : numOfToken,
            sender : sender
            });

        bytes32 bidHash = calculateBidHash(sender, price, numOfToken, useWholeAmount);

        // Save and fire event
        bids[bidHash] = bid;
        senderBidHash[sender].push(bidHash);
        emit BidAccepted(sender, price, value);

        received_wei = received_wei.add(value);

        bidSeq.push(bid);

        if (useWholeAmount) {
            amount_in_bid = amount_in_bid.add(value);
        } else {
            tokens_in_bid = tokens_in_bid.add(numOfToken);
        }

        //wallet_address.transfer(value);
        //emit FundsTransfered(sender, wallet_address, value);
    }

    // Setup auction
    function startAuction() public isOwner isSaleOn atStage(Stages.AuctionDeployed) {
        // Update auction stage and fire event
        start_time = block.timestamp;
        interval_start_time = start_time;
        current_stage = Stages.AuctionStarted;

        if (preBidders[price_start].exist) {
            placePreBid(price_start);
        }

        emit AuctionStarted(start_time);
    }

    // End auction
    function endAuction() external isOwner atStage(Stages.AuctionStarted) {
        endImmediately(price_current, Endings.Manual);
    }

    // Inner function for ending auction
    function endImmediately(uint256 atPrice, Endings ending) private atStage(Stages.AuctionStarted) {
        end_time = block.timestamp;
        price_final = atPrice;

        uint256 amountInBid = amount_in_bid;
        uint256 tokensInBid = tokens_in_bid;

        if (tokensInBid.add(amountInBid.div(price_final)) > initial_offering) {

            uint256 extraTokensAllocated = tokensInBid.add(amountInBid.div(price_final)).sub(initial_offering);

            for (uint a = bidSeq.length - 1; a >= 0; a--) {
                uint256 bidValue = bidSeq[a].value;
                uint256 numOfToken = bidSeq[a].numOfToken;

                uint256 assignedTokens;

                if (bidSeq[a].useWholeAmount) {
                    assignedTokens = bidValue.div(price_final);
                } else {
                    assignedTokens = numOfToken;
                }

                if (assignedTokens > extraTokensAllocated) {

                    uint256 tokenDifference = assignedTokens - extraTokensAllocated;
                    uint256 returnedWei = extraTokensAllocated.mul(price_final);

                    bidSeq[a].value = bidSeq[a].value.sub(returnedWei);
                    bidSeq[a].numOfToken = tokenDifference;

                    if (bidSeq[a].useWholeAmount) {
                        amount_in_bid = amount_in_bid.sub(returnedWei);
                    } else {
                        tokens_in_bid = tokens_in_bid.sub(extraTokensAllocated);
                    }

                    // Refund remaining value
                    if (refunds[msg.sender].amount > 0) {
                        refunds[msg.sender].amount = refunds[msg.sender].amount.add(returnedWei);
                    } else {
                        Refund memory refund = Refund({
                            amount : returnedWei,
                            refunded : false
                            });
                        refunds[msg.sender] = refund;
                    }
                    break;
                } else if (assignedTokens == extraTokensAllocated) {
                    bids[calculateBidHash(bidSeq[a].sender, bidSeq[a].price, bidSeq[a].numOfToken, bidSeq[a].useWholeAmount)].placed = false;
                    if (bidSeq[a].useWholeAmount) {
                        amount_in_bid = amount_in_bid.sub(bidValue);
                    } else {
                        tokens_in_bid = tokens_in_bid.sub(numOfToken);
                    }
                    break;
                } else {
                    bids[calculateBidHash(bidSeq[a].sender, bidSeq[a].price, bidSeq[a].numOfToken, bidSeq[a].useWholeAmount)].placed = false;
                    if (bidSeq[a].useWholeAmount) {
                        amount_in_bid = amount_in_bid.sub(bidValue);
                    } else {
                        tokens_in_bid = tokens_in_bid.sub(numOfToken);
                    }
                    continue;
                }
            }
        }

        current_stage = Stages.AuctionEnded;
        emit AuctionEnded(price_current, end_time, ending);
    }

    // Claim tokens
    function claimTokens() external atStage(Stages.AuctionEnded) {
        // Input validation
        require(block.timestamp >= end_time.add(claim_period), "Claim period has not started");
        require(senderBidHash[msg.sender].length > 0, "This bidder has no successful bids");

        for (uint a = senderBidHash[msg.sender].length; a > 0; a--) {
            if (bids[senderBidHash[msg.sender][a - 1]].placed == true && bids[senderBidHash[msg.sender][a - 1]].claimed == false) {
                Bid memory claimedBid = bids[senderBidHash[msg.sender][a - 1]];
                // Calculate tokens to receive
                uint256 tokens = claimedBid.useWholeAmount ? claimedBid.value.div(price_final) : claimedBid.numOfToken;
                uint256 auctionTokensBalance = token.balanceOf(owner_address);
                if (tokens > auctionTokensBalance) {
                    // Unreachable code
                    tokens = auctionTokensBalance;
                }

                bids[senderBidHash[msg.sender][a - 1]].claimed = true;

                // Transfer tokens and fire event
                token.transferFrom(owner_address, msg.sender, tokens * 10**18);
                emit TokensClaimed(msg.sender, tokens);

                //Update the total amount of funds for which tokens have been claimed and check for refunds
                if (claimedBid.useWholeAmount) {
                    claimed_wei = claimed_wei + claimedBid.value;
                } else {
                    uint256 usedWei = claimedBid.numOfToken.mul(price_final);
                    claimed_wei = claimed_wei + usedWei;
                    if (refunds[msg.sender].amount > 0) {
                        refunds[msg.sender].amount = refunds[msg.sender].amount.add(claimedBid.value.sub(usedWei));
                    } else {
                        Refund memory refund = Refund({
                            amount : claimedBid.value.sub(usedWei),
                            refunded : false
                            });
                        refunds[msg.sender] = refund;
                    }
                }

                // Set new state if all tokens distributed
                if (claimed_wei >= received_wei) {
                    current_stage = Stages.TokensDistributed;
                    emit TokensDistributed();
                }
            }
        }
    }

    function claimRefund() external atStageOr(Stages.AuctionEnded, Stages.TokensDistributed) {
        require(refunds[msg.sender].refunded == false);

        uint256 amountToRefund = refunds[msg.sender].amount;

        for (uint a = senderBidHash[msg.sender].length; a > 0; a--) {
            if (bids[senderBidHash[msg.sender][a - 1]].placed == false) {
                amountToRefund = amountToRefund.add(bids[senderBidHash[msg.sender][a - 1]].value);
            }
        }
        //update the actual amount being refunded
        refunds[msg.sender].amount = amountToRefund;

        refunds[msg.sender].refunded = true;

        claimed_wei = claimed_wei.add(amountToRefund);

        if (claimed_wei >= received_wei) {
            current_stage = Stages.TokensDistributed;
            emit TokensDistributed();
        }

        // Transfer amount to msg.sender from contract account
        msg.sender.transfer(amountToRefund);
        emit BidRefunded(msg.sender, amountToRefund);

    }

    // To be called by external API to check whether a price update is required
    function needToBeUpdated() public view isOwner atStage(Stages.AuctionStarted) returns (bool){
        return (block.timestamp - interval_start_time >= intervals_duration);
    }

    //To be called by external API to update price, when no bid occur during interval duration
    function updatePrice() public isOwner atStage(Stages.AuctionStarted) {
        require(price_current >= price_reserve);
        if (price_current == price_reserve) {
            if (preBidders[price_current].exist) {
                placePreBid(price_reserve);
            }
            endImmediately(price_reserve, Endings.ReservePriceReached);
        } else {
            price_current = price_current.sub(price_change);
            price_final = price_current;
            interval_start_time = block.timestamp;
            if (preBidders[price_current].exist) {
                placePreBid(price_current);
            }
        }
    }

    // To place absentee bids
    function placePreBid(uint256 price) internal atStage(Stages.AuctionStarted) {
        bytes32[] memory bidHashes = preBidders[price].bidHashes;

        for (uint a = 0; a < bidHashes.length; a++) {
            Bid storage preBid = bids[bidHashes[a]];
            if (preBid.placed == false) {
                preBid.placed = true;

                if (preBid.useWholeAmount) {
                    amount_in_bid = amount_in_bid.add(preBid.value);
                } else {
                    tokens_in_bid = tokens_in_bid.add(preBid.numOfToken);
                }

                bidSeq.push(preBid);
            }
        }
    }

    // Transfer unused tokens back to the wallet
    function transferBack() external isOwner atStage(Stages.TokensDistributed) {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0);
        token.transfer(wallet_address, balance);
    }

    // Owner can change stage in an emergency situation
    function changeStage(Stages stage) public isOwner {
        current_stage = stage;
    }

    function getTokenBal(address accAddress) public view returns (uint){
        return token.balanceOf(accAddress);
    }

    function getPreBidders(uint256 price) public view isOwner returns (bytes32[]) {
        return preBidders[price].bidHashes;
    }

    function transferWeiToOwner(uint256 _amount) isOwner external {
        /**
         * Withdraw wei collected by the contract. Only the owner can call this.
         */
        require(_amount <= getContractBalance()); // Also prevents underflow
        wallet_address.transfer(_amount);
    }

    function intervalCountdown() public view isOwner atStage(Stages.AuctionStarted) returns (uint256){
        return (intervals_duration - (block.timestamp - interval_start_time));
    }

    function totalTokensInBid() public view atStage(Stages.AuctionStarted) returns (uint256){
        return tokens_in_bid.add(amount_in_bid.div(price_current));
    }

    function calculateBidHash(address sender, uint256 price, uint256 numOfToken, bool useWholeAmount) internal pure returns (bytes32){
        return keccak256(abi.encodePacked(sender, price, numOfToken, useWholeAmount));
    }

    function getBidHashes(address bidder) public view returns (bytes32[]){
        return senderBidHash[bidder];
    }

    function noOfBids(address bidder) public view returns (uint){
        return senderBidHash[bidder].length;
    }

    function getContractBalance() public view returns (uint256){
        return address(this).balance;
    }
}
