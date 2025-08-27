// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRamp} from './interface/IRamp.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@arewageek/access-control/contracts/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Ramp is IRamp, ReentrancyGuard {
    uint256 private requestsCount;
    bytes32 public constant ADMIN = keccak256("admin");
    bytes32 public constant OPERATOR = keccak256("operator");
    bytes32 public constant CREATOR = keccak256("creator");

    mapping (uint256 => RampRequest) public requests;
    mapping (address => uint256[]) public userRequests;
    mapping (address => bool) public supportedTokens;

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
        if (requestsCount < _id) {
            revert InvalidRequest(_id);
        }
        _;
    }


    modifier isSupportedToken(address _token){
        if(!supportedTokens[_token]){
            revert UnsupportedToken(_token);
        }
        _;
    }

    constructor() {
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
        if(!supportedTokens[_token]){
            revert UnsupportedToken(_token);
        }

        unchecked {
            requestsCount++;
        }

        RampRequest memory newRequest = RampRequest({
            id: requestsCount,
            user: _user,
            token: _token,
            amount: _amount,
            rampType: _rampType,
            status: Status.PENDING,
            createdAt: block.timestamp
        });

        requests[requestsCount] = newRequest;
        userRequests[_user].push(requestsCount);

        emit RequestCreated(
            requestsCount,
            _user,
            _token,
            _amount,
            _rampType,
            block.timestamp
        );

        return requestsCount;
    }

    // onramping
    function fundEscrow(uint256 _id) external payable nonReentrant validRequest(_id) {
        RampRequest storage request = requests[_id];

        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }
        if (request.rampType != RampType.CRYPTO_TO_FIAT) {
            revert InvalidRampType(_id, request.rampType, RampType.CRYPTO_TO_FIAT);
        }
        
        IERC20 token = IERC20(request.token);
        uint256 allowance = token.allowance(msg.sender, address(this));
        uint256 balance = token.balanceOf(msg.sender);
        
        if (allowance < request.amount) {
            revert InsufficientBalance(request.token, request.amount, allowance);
        }
        if (balance < request.amount) {
            revert InsufficientBalance(request.token, request.amount, balance);
        }
        
        _transfer(request.amount, msg.sender, address(this));

        request.status = Status.COMPLETED;

        emit EscrowFunded(_id, msg.sender, request.amount, block.timestamp);
    }
    // off ramping
    function releaseEscrow(uint256 _id) external operatorOrAdmin nonReentrant validRequest(_id) {
        RampRequest storage request = requests[_id];
        
        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }
        if (request.rampType != RampType.FIAT_TO_CRYPTO) {
            revert InvalidRampType(_id, request.rampType, RampType.FIAT_TO_CRYPTO);
        }

        request.status = Status.COMPLETED;

        _transfer(request.amount, request.user, request.token);

        emit EscrowReleased(_id, request.user, request.amount, block.timestamp);
    }

    function cancelRequest(uint256 _id) external onlyCreator(_id) nonReentrant validRequest(_id) {
        _terminate(_id);

        emit RequestRejected(_id, msg.sender);
    }

    function rejectRequest(uint256 _id) external operatorOrAdmin nonReentrant validRequest(_id) {
        _terminate(_id);

        emit RequestRejected(_id, msg.sender);
    }

    receive() external payable {}

    // admin functions

    function addToken(address _token) external onlyAdmin {
        if(_token == address(0)){
            revert ZeroAddress();
        }
        
        supportedTokens[_token] = true;

        emit TokenSupportAdded(_token);
    }

    function removeToken(address _token) external onlyAdmin isSupportedToken(_token){        
        supportedTokens[_token] = false;

        emit TokenSupportRemoved(_token);
    }

    function _transfer(uint256 _amount, address _to, address _token) internal nonReentrant {
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

    function _terminate (uint256 _id) internal {
        RampRequest storage request = requests[_id];
        
        if (request.status != Status.PENDING) {
            revert InvalidStatus(_id, request.status, Status.PENDING);
        }

        request.status = Status.REJECTED;

        if (request.rampType == RampType.CRYPTO_TO_FIAT) {
            _transfer(request.amount, request.user, request.token);
        }
    }
}