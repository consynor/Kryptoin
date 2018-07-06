pragma solidity ^0.4.24;

import "./Z_Ownable.sol";
import "./DutchAuction.sol";

contract ICO is Ownable{

    struct ICOPhase {
        string phaseName;
        uint256 tokensStaged;
        uint256 tokensAllocated;
        uint256 startPrice;
        uint256 finalPrice;
        bool saleOn;
    }

    uint8 public currentICOPhase;

    mapping(address=>uint256) public ethContributedBy;
    uint256 public totalEthRaised;
    uint256 public totalTokensSoldTillNow;

    mapping(uint8=>ICOPhase) public icoPhases;
    uint8 icoPhasesIndex=1;

    address tokenAddress;

    constructor(address _tokenAddress) public{
        tokenAddress = _tokenAddress;
    }

    function getEthContributedBy(address _address) public constant returns(uint256){
        return ethContributedBy[_address];
    }

    function getTotalEthRaised() public constant returns(uint256){
        return totalEthRaised;
    }

    function getTotalTokensSoldTillNow() public constant returns(uint256){
        return totalTokensSoldTillNow;
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

        auction.startAuction(_tokenAddress, offering);

    }

    function toggleSaleStatus() public onlyOwner{
        icoPhases[currentICOPhase].saleOn = !icoPhases[currentICOPhase].saleOn;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

}
