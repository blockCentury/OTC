pragma solidity ^0.4.4;
import './SafeMath.sol';
import './StandardToken.sol';

contract owned {
    address public owner;

    function owned() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _;
    }

    function transferOwnership(address newOwner) onlyOwner {
        owner = newOwner;
    }
}

contract tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData); }

contract MeridianToken is owned, StandardToken, SafeMath {

    uint64 public sellPrice;
    uint64 public buyPrice;
    string public standard = 'Token 0.1';
    string public name = "Meridian Token";
    string public symbol = "MRT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    uint64 public dividendNumerator = 3;
    uint64 public dividendDenominator = 100;

    /* This creates an array with all balances */
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping (address => uint256) public unlockDate;
    mapping (address => bool) public frozenAccount;

    /* This generates a public event on the blockchain that will notify clients */
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    /* This generates a public event on the blockchain that will notify clients */
    event FrozenFunds(address target, bool frozen);

    event NotEnoughFunds(address account, uint256 currentBalance, uint256 need);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    function MeridianToken(
        uint256 initialSupply,
        string tokenName,
        uint8 decimalUnits,
        string tokenSymbol,
        uint64 tokenBuyPrice,
        uint64 tokenSellPrice
    ) { 
        balanceOf[msg.sender] = initialSupply;              // Give the creator all initial tokens
        totalSupply = initialSupply;                        // Update total supply
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
        decimals = decimalUnits;                            // Amount of decimals for display purposes
        owner = msg.sender;
        buyPrice = tokenBuyPrice;
        sellPrice = tokenSellPrice;
    }

    /* Allow another contract to spend some tokens in your behalf */
    function approve(address _spender, uint256 _value)
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    function lockAccount(address _target) internal {
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }

    function lock(address _target) onlyOwner {
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }

    function requestLock(uint how_many_minutes) returns(bool _success){
        unlockDate[msg.sender] = now + how_many_minutes * 1 minutes;
        lockAccount(msg.sender);
        return true;
    }      

    function unlockAccount(address _locked) internal {
        frozenAccount[_locked] = false;
        FrozenFunds(_locked, false);
    }

    function unlock(address _locked) onlyOwner {
        frozenAccount[_locked] = false;
        FrozenFunds(_locked, false);
    }

    function requestReward() returns(bool _success){
        if(now < unlockDate[msg.sender]) throw;
        unlockAccount(msg.sender);
        issueReward(msg.sender);
        return true;
    }

    function getUnlockDate(address _user) constant returns(uint date){
        return unlockDate[_user];
    }
    
    function issueReward(address _to) internal{
        transfer(_to, (balanceOf[_to] * dividendDenominator)/dividendNumerator);
        Transfer(msg.sender, _to, 1);
    }

    /* Send coins */
    function transfer(address _to, uint256 _value) {
        if (balanceOf[msg.sender] < _value) throw;           // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) throw; // Check for overflows
        if (frozenAccount[msg.sender]) throw; // Check if frozen          
        // if (_to.balance<minBalanceForAccounts)    //let the receiver pay ether to execute the transfer
        //     _to.send(sell((minBalanceForAccounts - _to.balance)/sellPrice));
        
        balanceOf[msg.sender] -= _value;                     // Subtract from the sender
        balanceOf[_to] += _value;                            // Add the same to the recipient
        Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
    }


    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) /*returns (bool success)*/ {
        if (frozenAccount[_from]) throw;                        // Check if frozen            
        if (balanceOf[_from] < _value) throw;                 // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) throw;  // Check for overflows
        // if (_value > allowance[_from][msg.sender]) throw;   // Check allowance
        // if (_to.balance<minBalanceForAccounts)    //let the receiver pay ether to execute the transfer
        //     _to.send(sell((minBalanceForAccounts - _to.balance)/sellPrice));

        balanceOf[_from] -= _value;                          // Subtract from the sender
        balanceOf[_to] += _value;                            // Add the same to the recipient
        // allowance[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
        // return true;
    }

    function mintToken(address target, uint256 mintedAmount) onlyOwner {
        balanceOf[target] += mintedAmount;
        totalSupply += mintedAmount;
        Transfer(0, this, mintedAmount);
        Transfer(this, target, mintedAmount);
    }
/*you can make the token's value be backed by ether (or other tokens) by 
creating a fund that automatically sells and buys them at market value*/
    function setPrices(uint64 newSellPrice, uint64 newBuyPrice) onlyOwner {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }
// people can buy my shares and pay wei
    function buy() payable returns (uint amount){
        uint shares = msg.value / buyPrice;               
        balanceOf[msg.sender] += shares;     // adds the amount to buyer's balance
        balanceOf[this] -= shares;          // subtracts amount from seller's balance
        Transfer(this, msg.sender, shares);// execute an event reflecting the change
        return shares;                
    }
// people can sell their shares and get wei.
    function sell(uint256 amount) returns (uint revenue){
        if (balanceOf[msg.sender] < amount ) throw; // checks if the sender has enough to sell
        if (frozenAccount[msg.sender]) throw;

        balanceOf[this] += amount;          // adds the amount to owner's balance
        balanceOf[msg.sender] -= amount;   // subtracts the amount from seller's balance
        uint income = amount*sellPrice;               
        if (!msg.sender.send(income)) {        // sends ether to the seller. It's important
            throw;                              // to do this last to avoid recursion attacks
        } else {
            Transfer(msg.sender, this, amount); // executes an event reflecting on the change
            return income;            
        }               
    }

    function destroy() onlyOwner{ // so funds not locked in contract forever
        if (msg.sender == owner) { 
            suicide(owner); // send funds to organizer
        }
    }
}