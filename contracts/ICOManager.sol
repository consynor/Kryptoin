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

    address[] public auctions;
    address public currentAuction;

    mapping(uint8=>ICOPhase) public icoPhases;
    uint8 icoPhasesIndex=1;

    address public tokenAddress;

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
        uint256 _offering) public onlyOwner{
        icoPhases[icoPhasesIndex].phaseName = _phaseName;
        icoPhases[icoPhasesIndex].startPrice = _priceStart;
        icoPhases[icoPhasesIndex].finalPrice = 0;
        icoPhases[icoPhasesIndex].tokensStaged = _offering;
        icoPhases[icoPhasesIndex].tokensAllocated = 0;
        icoPhases[icoPhasesIndex].saleOn = false;
        icoPhasesIndex++;

        address auction = new DutchAuction(
            _priceStart, _priceReserve, _minimumBid,
            _claimPeriod, _walletAddress, _intervalDuration,
            _offering, tokenAddress, owner);

        auctions.push(auction);
        currentAuction = auction;
    }

    function toggleSaleStatus() public onlyOwner{
        icoPhases[currentICOPhase].saleOn = !icoPhases[currentICOPhase].saleOn;
        DutchAuction auc = DutchAuction(auctions[auctions.length - 1]);
        auc.toggleSaleOn();
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

    function toggleTradeOn() public onlyOwner {
        KrpToken krp = KrpToken(tokenAddress);
        krp.toggleTradeOn();
    }

    function getAuctions() public view returns(address[]){
        return auctions;
    }
}