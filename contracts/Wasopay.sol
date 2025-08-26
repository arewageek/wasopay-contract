// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IWasoPay} from './interface/IWasoPay.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@arewageek/access-control/contracts/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract WasoPay is IWasoPay, ReentrancyGuard {
    uint256 private rampRequestsCount;
    bytes32 public constant ADMIN = keccak256("admin");
    bytes32 public constant OPERATOR = keccak256("operator");
    bytes32 public constant CREATOR = keccak256("creator");

    mapping (uint256 => RampRequest) public requests;
    mapping (address => uint256[]) public userRequests;

    AccessControl public immutable ac;

    modifier onlyOperator() {
        if (!ac.has(OPERATOR, msg.sender)) {
            revert UnauthorizedAccess(msg.sender, OPERATOR);
        }
        _;
    }

    modifier onlyAdmin() {
        if (!ac.has(ADMIN, msg.sender)) {
            revert UnauthorizedAccess(msg.sender, ADMIN);
        }
        _;
    }

    modifier operatorOrAdmin() {
        if (!ac.has(OPERATOR, msg.sender) && !ac.has(ADMIN, msg.sender)) {
            revert UnauthorizedAccess(msg.sender, OPERATOR);
        }
        _;
    }

    modifier onlyCreator(uint256 _id) {
        if (requests[_id].user != msg.sender) {
            revert UnauthorizedAccess(msg.sender, CREATOR);
        }
        _;
    }

    modifier validRequest(uint256 _id) {
        if (requests[_id].id == 0) {
            revert InvalidRequest(_id);
        }
        _;
    }

    constructor(address _accessControl) {
        if (_accessControl == address(0)) {
            revert ZeroAddress();
        }
        ac = AccessControl(_accessControl);
        
    
        ac.grant(ADMIN, msg.sender);
    }

    function createRequest(
        address _user,
        address _token,
        uint256 _amount,
        RampType _rampType
    ) external onlyOperator returns (uint256) {
        if (_user == address(0)) {
            revert ZeroAddress();
        }
        if (_amount == 0) {
            revert ZeroAmount();
        }

        unchecked {
            ++rampRequestsCount;
        }

        RampRequest memory newRequest = RampRequest({
            id: rampRequestsCount,
            user: _user,
            token: _token,
            amount: _amount,
            rampType: _rampType,
            status: Status.PENDING,
            createdAt: block.timestamp
        });

        requests[rampRequestsCount] = newRequest;
        userRequests[_user].push(rampRequestsCount);

        emit RequestCreated(
            rampRequestsCount,
            _user,
            _token,
            _amount,
            _rampType,
            block.timestamp
        );

        return rampRequestsCount;
    }

    function fundEscrow(uint256 _id) external payable nonReentrant validRequest(_id) {
        RampRequest storage request = requests[_id];

        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }
        if (request.rampType != RampType.CRYPTO_TO_FIAT) {
            revert InvalidRampType(_id, request.rampType, RampType.CRYPTO_TO_FIAT);
        }

    
        if (request.token == address(0)) {
            if (msg.value != request.amount) {
                revert InsufficientBalance(address(0), request.amount, msg.value);
            }
        } else {
        
            IERC20 token = IERC20(request.token);
            uint256 allowance = token.allowance(msg.sender, address(this));
            uint256 balance = token.balanceOf(msg.sender);
            
            if (allowance < request.amount) {
                revert InsufficientBalance(request.token, request.amount, allowance);
            }
            if (balance < request.amount) {
                revert InsufficientBalance(request.token, request.amount, balance);
            }
            
            bool success = token.transferFrom(msg.sender, address(this), request.amount);
            if (!success) {
                revert TransferFailed(request.token, address(this), request.amount);
            }
        }

        Status oldStatus = request.status;
        request.status = Status.COMPLETED;

        emit EscrowFunded(_id, msg.sender, request.amount, block.timestamp);
        emit RequestStatusChanged(_id, oldStatus, Status.COMPLETED, block.timestamp);
    }

    function releaseEscrow(uint256 _id) external operatorOrAdmin nonReentrant validRequest(_id) {
        RampRequest storage request = requests[_id];
        
        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }
        if (request.rampType != RampType.FIAT_TO_CRYPTO) {
            revert InvalidRampType(_id, request.rampType, RampType.FIAT_TO_CRYPTO);
        }

        Status oldStatus = request.status;
        request.status = Status.COMPLETED;

        _transfer(request.amount, request.user, request.token);

        emit EscrowReleased(_id, request.user, request.amount, block.timestamp);
        emit RequestStatusChanged(_id, oldStatus, Status.COMPLETED, block.timestamp);
    }

    function rejectRequest(uint256 _id) external operatorOrAdmin nonReentrant validRequest(_id) {
        RampRequest storage request = requests[_id];
        
        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }

        Status oldStatus = request.status;
        request.status = Status.REJECTED;

    
        if (request.rampType == RampType.CRYPTO_TO_FIAT) {
            _transfer(request.amount, request.user, request.token);
        }

        emit RequestStatusChanged(_id, oldStatus, Status.REJECTED, block.timestamp);
    }

    function getUserRequests(address _user) external view returns (uint256[] memory) {
        return userRequests[_user];
    }

    function getRequestsCount() external view returns (uint256) {
        return rampRequestsCount;
    }

    function _transfer(uint256 _amount, address _to, address _token) internal {
        if (_token == address(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            if (!success) {
                revert TransferFailed(_token, _to, _amount);
            }
        } else {
            bool success = IERC20(_token).transfer(_to, _amount);
            if (!success) {
                revert TransferFailed(_token, _to, _amount);
            }
        }
    }


    function emergencyWithdraw(address _token, uint256 _amount) external onlyAdmin {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        
        _transfer(_amount, msg.sender, _token);
    }


    receive() external payable {}
}