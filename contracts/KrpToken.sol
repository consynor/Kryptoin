pragma solidity ^0.5.4;

import "./Z_StandardToken.sol";
import "./Z_Ownable.sol";

contract KrpToken is StandardToken, Ownable {

    string public constant name = "Kryptoin";
    string public constant symbol = "KRP-TEST";
    uint8 public constant decimals = 18;

    event Mint(address indexed to, uint256 amount);
    event MintStopped();
    event MintStarted();
    bool public mintingStopped = false;
    bool public tradeOn = true;

    address mintManager;

    modifier canMint() {
        require(msg.sender == owner || msg.sender == mintManager);
        require(!mintingStopped);
        _;
    }

    modifier isTradeOn() {
        require(tradeOn == true);
        _;
    }

    function setMintManager(address _mintManager) public onlyOwner {
        mintManager = _mintManager;
    }

    /**
    * @dev Internal function that mints an amount of the token and assigns it to
    * an account.
    * @param account The account that will receive the created tokens.
    * @param amount The amount that will be created.
    */
    function mint(address account, uint256 amount) public canMint() returns(bool) {
        require(account != address(0));
        totalSupply_ = totalSupply_.add(amount);
        balances[account] = balances[account].add(amount);
        emit Mint(account, amount);
        emit Transfer(address(0), account, amount);
        return true;
    }

    /**
     * @dev Function to stop minting new tokens.
     * @return True if the operation was successful.
     */
    function stopMinting() onlyOwner public returns (bool) {
        mintingStopped = true;
        emit MintStopped();
        return true;
    }

    function startMinting() onlyOwner public returns (bool) {
        mintingStopped = false;
        emit MintStarted();
        return true;
    }

    event Burn(address indexed account, uint256 value);

    /**
     * @dev Function that burns an amount of the token of a given
     * account.
     * @param account The account whose tokens will be burnt.
     * @param amount The amount that will be burnt.
     */
    function burn(address account, uint256 amount) public canMint() {
        require(account != address(0));
        require(amount <= balances[account]);

        totalSupply_ = totalSupply_.sub(amount);
        balances[account] = balances[account].sub(amount);
        emit Burn(account, amount);
        emit Transfer(account, address(0), amount);
    }

    // Overrided to put modifier
    function transfer(address _to, uint256 _value) public isTradeOn returns (bool) {
        super.transfer(_to, _value);
    }

    // Overrided to put modifier
    function transferFrom(address _from, address _to, uint256 _value) public isTradeOn returns (bool) {
        super.transferFrom(_from, _to, _value);
    }

    // Toggle trade on/off
    function toggleTradeOn() public onlyOwner{
        tradeOn = !tradeOn;
    }
}
