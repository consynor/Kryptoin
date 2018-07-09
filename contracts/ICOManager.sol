pragma solidity ^0.4.24;

import "./Z_Ownable.sol";
import "./DutchAuction.sol";
import "./KrpToken.sol";

contract ICOManager is Ownable{

    struct ICOPhase {
        string phaseName;
        uint256 tokensStaged;
        uint256 tokensAllocated;
        uint256 startPrice;
        uint256 finalPrice;
        bool saleOn;
    }

    uint8 public currentICOPhase;

    mapping(uint8 => DutchAuction) auctions;
    uint8 auctionIndex = 1;

    mapping(uint8=>ICOPhase) public icoPhases;
    uint8 icoPhasesIndex=1;

    address tokenAddress;

    constructor(address _tokenAddress) public{
        tokenAddress = _tokenAddress;
    }

    function addICOPhase(
        string _phaseName,
        uint256 _priceStart,
        uint256 _priceReserve,
        uint256 _minimumBid,
        uint256 _claimPeriod,
        address _walletAddress,
        uint256 _intervalDuration,
        address _tokenAddress,
        uint256 offering) public onlyOwner{
        icoPhases[icoPhasesIndex].phaseName = _phaseName;
        icoPhases[icoPhasesIndex].startPrice = _priceStart;
        icoPhases[icoPhasesIndex].tokensStaged = offering;
        icoPhases[icoPhasesIndex].tokensAllocated = 0;
        icoPhases[icoPhasesIndex].saleOn = false;
        icoPhasesIndex++;

        DutchAuction auction = new DutchAuction(
            _priceStart, _priceReserve, _minimumBid, _claimPeriod, _walletAddress, _intervalDuration);

        auctions[auctionIndex] = auction;
        auctionIndex++;

        auction.startAuction(_tokenAddress, offering);
    }

    function toggleSaleStatus() public onlyOwner{
        icoPhases[currentICOPhase].saleOn = !icoPhases[currentICOPhase].saleOn;
        auctions[auctionIndex].toggleSaleOn();
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

    function toggleTradeOn() public onlyOwner {
        KrpToken(tokenAddress).toggleTradeOn();
    }
}