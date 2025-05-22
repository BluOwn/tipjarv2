// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./TipJarStructs.sol";

/**
 * @title TipJarBase
 * @dev Core functionality for the TipJar system - Now Upgradeable
 * @notice Official website: https://montip.xyz/
 */
contract TipJarBase is 
    Initializable, 
    ReentrancyGuardUpgradeable, 
    OwnableUpgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable 
{
    // Use structs from TipJarStructs
    using TipJarStructs for TipJarStructs.Tip;
    using TipJarStructs for TipJarStructs.JarInfo;

    // Fee percentage (1% = 100 / 10000)
    uint256 public constant PLATFORM_FEE_BASIS_POINTS = 100; 
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;
    
    // Address of the contract creator/fee recipient
    address public feeRecipient;
    
    // Emergency withdrawal delay (in seconds) - 24 hours
    uint256 public constant EMERGENCY_WITHDRAWAL_DELAY = 86400;
    
    // Timestamp when emergency withdrawal can be executed
    uint256 public emergencyWithdrawalUnlockTime;
    
    // Track whether an emergency withdrawal was used
    bool public emergencyWithdrawalUsed;
    
    // Minimum tip amount (0.01 ETH) to prevent spam
    uint256 public constant MIN_TIP_AMOUNT = 10000000000000000;
    
    // Mappings
    mapping(string => TipJarStructs.JarInfo) public jars;
    mapping(address => string) public ownerToUsername;
    mapping(string => TipJarStructs.Tip[]) public tipHistory;
    mapping(address => uint256) public failedTipAmounts;
    string[] public allUsernames;
    mapping(string => bool) private _normalizedUsernameExists;

    // Constants
    uint256 public constant MAX_USERNAME_LENGTH = 32;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 256;
    uint256 public constant MAX_MESSAGE_LENGTH = 280;
    uint256 public constant MAX_SOCIAL_KEY_LENGTH = 32;
    uint256 public constant MAX_SOCIAL_VALUE_LENGTH = 256;
    uint256 public constant MAX_SOCIAL_LINKS = 10;
    
    // Events
    event JarCreated(address indexed owner, string username);
    event JarDeleted(address indexed owner, string username);
    event JarDeletedByAdmin(address indexed admin, address indexed owner, string username);
    event TipSent(address indexed sender, string indexed toUsername, uint256 totalAmount, string message, uint256 tipAmount, uint256 fee);
    event TipFailed(address indexed recipient, uint256 amount);
    event TipReceived(address indexed recipient, uint256 amount);
    event FailedTipWithdrawn(address indexed recipient, uint256 amount);
    event FeePaid(address indexed recipient, uint256 amount);
    event FeeRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    event EmergencyWithdrawalInitiated(address indexed initiator, uint256 amount, uint256 unlockTime);
    event EmergencyWithdrawalCancelled(address indexed initiator);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        feeRecipient = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    function websiteURL() public pure returns (string memory) {
        return "https://montip.xyz/";
    }

    modifier usernameAvailable(string memory username) {
        require(!jars[username].exists, "Username already taken");
        string memory normalizedUsername = _toLower(username);
        require(!_normalizedUsernameExists[normalizedUsername], "Username already taken (case-insensitive)");
        _;
    }

    modifier jarExists(string memory username) {
        require(jars[username].exists, "Tip jar does not exist");
        _;
    }

    modifier validUsername(string memory username) {
        require(bytes(username).length > 0, "Username cannot be empty");
        require(bytes(username).length <= MAX_USERNAME_LENGTH, "Username too long");
        require(_isValidUsername(username), "Username contains invalid characters");
        _;
    }

    function _isValidUsername(string memory str) internal pure returns (bool) {
        bytes memory b = bytes(str);
        for (uint i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (
                !(c >= 0x30 && c <= 0x39) && // 0-9
                !(c >= 0x41 && c <= 0x5A) && // A-Z
                !(c >= 0x61 && c <= 0x7A) && // a-z
                !(c == 0x5F) &&              // _
                !(c == 0x2D) &&              // -
                !(c == 0x2E)                 // .
            ) {
                return false;
            }
        }
        return true;
    }

    function pause() public onlyOwner {
        _pause();
    }
    
    function unpause() public onlyOwner {
        _unpause();
    }

    function createJar(string memory username, string memory description) 
        public 
        whenNotPaused
        usernameAvailable(username)
        validUsername(username)
    {
        require(bytes(ownerToUsername[msg.sender]).length == 0, "You already have a jar");
        require(bytes(description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        
        TipJarStructs.JarInfo storage newJar = jars[username];
        newJar.owner = msg.sender;
        newJar.username = username;
        newJar.description = description;
        newJar.totalReceived = 0;
        newJar.exists = true;
        
        string memory normalizedUsername = _toLower(username);
        _normalizedUsernameExists[normalizedUsername] = true;
        
        ownerToUsername[msg.sender] = username;
        allUsernames.push(username);
        
        emit JarCreated(msg.sender, username);
    }

    function deleteJar() public {
        string memory username = ownerToUsername[msg.sender];
        require(bytes(username).length > 0, "You don't have a jar");
        
        _performJarDeletion(msg.sender, username);
        
        emit JarDeleted(msg.sender, username);
    }

    // NEW: Admin can delete any jar
    function adminDeleteJar(string memory username) public onlyOwner jarExists(username) {
        address jarOwner = jars[username].owner;
        
        _performJarDeletion(jarOwner, username);
        
        emit JarDeletedByAdmin(msg.sender, jarOwner, username);
    }

    // NEW: Admin can delete jar by owner address
    function adminDeleteJarByOwner(address jarOwner) public onlyOwner {
        string memory username = ownerToUsername[jarOwner];
        require(bytes(username).length > 0, "User doesn't have a jar");
        
        _performJarDeletion(jarOwner, username);
        
        emit JarDeletedByAdmin(msg.sender, jarOwner, username);
    }

    // MODIFIED: Now usernames can be reused after deletion
    function _performJarDeletion(address jarOwner, string memory username) internal {
        // Clear owner to username mapping
        delete ownerToUsername[jarOwner];
        
        // Clear social links
        for (uint256 i = 0; i < jars[username].socialLinkKeys.length; i++) {
            delete jars[username].socialLinks[jars[username].socialLinkKeys[i]];
        }
        
        while (jars[username].socialLinkKeys.length > 0) {
            jars[username].socialLinkKeys.pop();
        }
        
        string memory normalizedUsername = _toLower(username);
        
        // CHANGED: Allow username reuse by clearing the normalized mapping
        delete _normalizedUsernameExists[normalizedUsername];
        
        // Mark jar as non-existent (but keep tip history)
        jars[username].exists = false;
        jars[username].owner = address(0);
        jars[username].username = "";
        jars[username].description = "";
        jars[username].totalReceived = 0;
        
        // Remove from allUsernames array
        for (uint256 i = 0; i < allUsernames.length; i++) {
            if (keccak256(bytes(allUsernames[i])) == keccak256(bytes(username))) {
                allUsernames[i] = allUsernames[allUsernames.length - 1];
                allUsernames.pop();
                break;
            }
        }
        
        // NOTE: We keep tipHistory[username] intact for transparency
        // Users can still view historical tips even after jar deletion
    }

    function sendTip(string memory username, string memory message) 
        public 
        payable 
        whenNotPaused
        jarExists(username)
        nonReentrant 
    {
        require(msg.value >= MIN_TIP_AMOUNT, "Tip amount too small");
        require(bytes(message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        
        uint256 fee = (msg.value * PLATFORM_FEE_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
        uint256 tipAmount = msg.value - fee;
        
        jars[username].totalReceived += tipAmount;
        
        tipHistory[username].push(TipJarStructs.Tip({
            sender: msg.sender,
            amount: msg.value,
            message: message,
            timestamp: block.timestamp
        }));
        
        if (fee > 0) {
            (bool feeSuccess, ) = feeRecipient.call{value: fee}("");
            if (!feeSuccess) {
                failedTipAmounts[feeRecipient] += fee;
                emit TipFailed(feeRecipient, fee);
            }
            emit FeePaid(feeRecipient, fee);
        }
        
        (bool tipSuccess, ) = jars[username].owner.call{value: tipAmount}("");
        if (!tipSuccess) {
            failedTipAmounts[jars[username].owner] += tipAmount;
            emit TipFailed(jars[username].owner, tipAmount);
        }
        
        emit TipSent(msg.sender, username, msg.value, message, tipAmount, fee);
    }

    function withdrawFailedTips() public nonReentrant {
        uint256 amount = failedTipAmounts[msg.sender];
        require(amount > 0, "No failed tips to withdraw");
        
        failedTipAmounts[msg.sender] = 0;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit FailedTipWithdrawn(msg.sender, amount);
    }

    function setFeeRecipient(address newFeeRecipient) public onlyOwner {
        require(newFeeRecipient != address(0), "Invalid address");
        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientChanged(oldRecipient, newFeeRecipient);
    }

    function getJarInfo(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (address owner, string memory description, uint256 totalReceived) 
    {
        TipJarStructs.JarInfo storage jar = jars[username];
        return (jar.owner, jar.description, jar.totalReceived);
    }

    function hasJar(address user) public view returns (bool) {
        return bytes(ownerToUsername[user]).length > 0;
    }

    function getUserJar(address user) public view returns (string memory) {
        require(bytes(ownerToUsername[user]).length > 0, "User has no jar");
        return ownerToUsername[user];
    }
    
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        
        return string(bLower);
    }
    
    function initiateEmergencyWithdrawal() public onlyOwner {
        require(
            emergencyWithdrawalUnlockTime == 0 || 
            block.timestamp > emergencyWithdrawalUnlockTime + EMERGENCY_WITHDRAWAL_DELAY, 
            "Withdrawal already initiated and still valid"
        );
        
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        emergencyWithdrawalUnlockTime = block.timestamp + EMERGENCY_WITHDRAWAL_DELAY;
        
        emit EmergencyWithdrawalInitiated(owner(), balance, emergencyWithdrawalUnlockTime);
    }
    
    function emergencyWithdraw() public onlyOwner nonReentrant {
        require(emergencyWithdrawalUnlockTime > 0, "Withdrawal not initiated");
        require(block.timestamp >= emergencyWithdrawalUnlockTime, "Withdrawal still locked");
        require(address(this).balance > 0, "No balance to withdraw");
        
        uint256 balance = address(this).balance;
        
        emergencyWithdrawalUnlockTime = 0;
        emergencyWithdrawalUsed = true;
        
        (bool success, ) = owner().call{value: balance}("");
        require(success, "Emergency withdrawal failed");
        
        emit EmergencyWithdrawal(owner(), balance);
    }
    
    function cancelEmergencyWithdrawal() public onlyOwner {
        require(emergencyWithdrawalUnlockTime > 0, "No withdrawal to cancel");
        
        emergencyWithdrawalUnlockTime = 0;
        
        emit EmergencyWithdrawalCancelled(owner());
    }

    // NEW: Function to check if username is available (for frontend)
    function isUsernameAvailable(string memory username) public view returns (bool) {
        if (jars[username].exists) return false;
        
        string memory normalizedUsername = _toLower(username);
        return !_normalizedUsernameExists[normalizedUsername];
    }

    // NEW: Get contract version for upgrade tracking
    function getVersion() public pure virtual returns (string memory) {
        return "v1.0.0";
    }
}