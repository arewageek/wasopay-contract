// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IWasoPay {
    // Enums
    enum Status {
        PENDING,
        COMPLETED,
        REJECTED
    }

    enum RampType {
        FIAT_TO_CRYPTO,
        CRYPTO_TO_FIAT
    }

    // Structs
    struct RampRequest {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        RampType rampType;
        Status status;
        uint256 createdAt;
    }

    // Events
    event RequestCreated(
        uint256 indexed requestId,
        address indexed user,
        address indexed token,
        uint256 amount,
        RampType rampType,
        uint256 timestamp
    );
    
    event EscrowFunded(
        uint256 indexed requestId,
        address indexed funder,
        uint256 amount,
        uint256 timestamp
    );
    
    event EscrowReleased(
        uint256 indexed requestId,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
    
    event RequestStatusChanged(
        uint256 indexed requestId,
        Status oldStatus,
        Status newStatus,
        uint256 timestamp
    );

    // Custom errors
    error InvalidRequest(uint256 requestId);
    error InvalidStatus(uint256 requestId, Status current, Status expected);
    error InvalidRampType(uint256 requestId, RampType current, RampType expected);
    error UnauthorizedAccess(address caller, bytes32 requiredRole);
    error TransferFailed(address token, address to, uint256 amount);
    error InsufficientBalance(address token, uint256 required, uint256 available);
    error ZeroAmount();
    error ZeroAddress();

    // Core functions
    function createRequest(
        address _user,
        address _token,
        uint256 _amount,
        RampType _rampType
    ) external returns (uint256);
    
    function fundEscrow(uint256 _id) external payable;
    function releaseEscrow(uint256 _id) external;
    function rejectRequest(uint256 _id) external;
    
    // View functions
    function getUserRequests(address _user) external view returns (uint256[] memory);
    function getRequestsCount() external view returns (uint256);
    
    // Admin functions
    function emergencyWithdraw(address _token, uint256 _amount) external;
}