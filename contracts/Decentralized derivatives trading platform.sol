// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Derivatives Trading Platform
 * @dev A smart contract for trading derivative contracts in a decentralized manner
 * @author DeFi Developer
 */
contract Project {
    
    // Struct to represent a derivative contract
    struct DerivativeContract {
        uint256 id;
        address creator;
        address counterparty;
        string underlying;
        uint256 strikePrice;
        uint256 premium;
        uint256 expirationTime;
        bool isActive;
        bool isSettled;
        ContractType contractType;
    }
    
    enum ContractType { CALL, PUT }
    
    // State variables
    mapping(uint256 => DerivativeContract) public contracts;
    mapping(address => uint256[]) public userContracts;
    uint256 public contractCounter;
    uint256 public constant PLATFORM_FEE = 100; // 1% in basis points
    address public owner;
    
    // Events
    event ContractCreated(uint256 indexed contractId, address indexed creator, string underlying, uint256 strikePrice);
    event ContractMatched(uint256 indexed contractId, address indexed counterparty);
    event ContractSettled(uint256 indexed contractId, address indexed winner, uint256 payout);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier contractExists(uint256 _contractId) {
        require(_contractId < contractCounter, "Contract does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        contractCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new derivative contract
     * @param _underlying The underlying asset (e.g., "ETH", "BTC")
     * @param _strikePrice The strike price for the derivative
     * @param _premium The premium amount in wei
     * @param _expirationTime The expiration timestamp
     * @param _contractType The type of contract (CALL or PUT)
     */
    function createContract(
        string memory _underlying,
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _expirationTime,
        ContractType _contractType
    ) external payable returns (uint256) {
        require(_expirationTime > block.timestamp, "Expiration must be in the future");
        require(msg.value >= _premium, "Insufficient premium payment");
        require(bytes(_underlying).length > 0, "Underlying asset cannot be empty");
        
        uint256 contractId = contractCounter++;
        
        contracts[contractId] = DerivativeContract({
            id: contractId,
            creator: msg.sender,
            counterparty: address(0),
            underlying: _underlying,
            strikePrice: _strikePrice,
            premium: _premium,
            expirationTime: _expirationTime,
            isActive: true,
            isSettled: false,
            contractType: _contractType
        });
        
        userContracts[msg.sender].push(contractId);
        
        emit ContractCreated(contractId, msg.sender, _underlying, _strikePrice);
        return contractId;
    }
    
    /**
     * @dev Core Function 2: Match with an existing derivative contract
     * @param _contractId The ID of the contract to match with
     */
    function matchContract(uint256 _contractId) external payable contractExists(_contractId) {
        DerivativeContract storage derivContract = contracts[_contractId];
        
        require(derivContract.isActive, "Contract is not active");
        require(derivContract.counterparty == address(0), "Contract already matched");
        require(derivContract.creator != msg.sender, "Cannot match with own contract");
        require(block.timestamp < derivContract.expirationTime, "Contract has expired");
        require(msg.value >= derivContract.premium, "Insufficient premium payment");
        
        derivContract.counterparty = msg.sender;
        userContracts[msg.sender].push(_contractId);
        
        // Transfer premium to contract creator (minus platform fee)
        uint256 platformFee = (derivContract.premium * PLATFORM_FEE) / 10000;
        uint256 creatorPayout = derivContract.premium - platformFee;
        
        payable(derivContract.creator).transfer(creatorPayout);
        payable(owner).transfer(platformFee);
        
        emit ContractMatched(_contractId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Settle a derivative contract
     * @param _contractId The ID of the contract to settle
     * @param _finalPrice The final price of the underlying asset at expiration
     */
    function settleContract(uint256 _contractId, uint256 _finalPrice) external contractExists(_contractId) {
        DerivativeContract storage derivContract = contracts[_contractId];
        
        require(derivContract.isActive, "Contract is not active");
        require(derivContract.counterparty != address(0), "Contract not matched");
        require(block.timestamp >= derivContract.expirationTime, "Contract not yet expired");
        require(!derivContract.isSettled, "Contract already settled");
        require(
            msg.sender == derivContract.creator || msg.sender == derivContract.counterparty,
            "Only contract parties can settle"
        );
        
        derivContract.isActive = false;
        derivContract.isSettled = true;
        
        address winner;
        uint256 payout = derivContract.premium * 2; // Total premium from both parties
        
        // Determine winner based on contract type and final price
        if (derivContract.contractType == ContractType.CALL) {
            winner = _finalPrice > derivContract.strikePrice ? derivContract.creator : derivContract.counterparty;
        } else { // PUT
            winner = _finalPrice < derivContract.strikePrice ? derivContract.creator : derivContract.counterparty;
        }
        
        // Transfer payout to winner (contract balance should have both premiums)
        if (address(this).balance >= payout) {
            payable(winner).transfer(payout);
        }
        
        emit ContractSettled(_contractId, winner, payout);
    }
    
    // View functions
    function getContract(uint256 _contractId) external view contractExists(_contractId) returns (DerivativeContract memory) {
        return contracts[_contractId];
    }
    
    function getUserContracts(address _user) external view returns (uint256[] memory) {
        return userContracts[_user];
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // Emergency functions
    function withdrawFees() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}
