// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IWasoPay {
    enum Status {
        PENDING,
        COMPLETED,
        REJECTED
    }

    enum RampType {
        FIAT_TO_CRYPTO,
        CRYPTO_TO_FIAT
    }

    struct RampRequest {
        uint256 id;
        address user;
        address token;
        uint256 amount;
        RampType rampType;
        Status status;
        uint256 createdAt;
    }

    function createRequest (
        address _user,
        address _token,
        uint256 _amount,
        RampType _rampType
    ) external returns (uint256);
    function fundEscrow (uint256 _id) external;
    function releaseEscrow (uint256 _id) external;
}