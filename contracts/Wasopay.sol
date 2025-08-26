// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IWasoPay} from './interface/IWasoPay.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@arewageek/access-control/contracts/AccessControl.sol";

contract WasoPay is IWasoPay {
    uint256 rampRequestsCount;
    bytes32 constant ADMIN = keccak256("admin");
    bytes32 constant OPERATOR = keccak256("operator");
    bytes32 constant CREATOR = keccak256("creator");

    mapping (uint256 => RampRequest) public requests;

    AccessControl public ac;

    modifier onlyOperator() {
        require(ac.has(OPERATOR, msg.sender), "Unauthorized: Only operator");
        _;
    }

    modifier onlyAdmin() {
        require(ac.has(ADMIN, msg.sender), "Unauthorized: Only admin");
        _;
    }

    modifier operatorOrAdmin() {
        require(ac.has(OPERATOR, msg.sender) || ac.has(ADMIN, msg.sender), "Unauthorized: Only operator or admin");
        _;
    }

    modifier onlyCreator (uint _id) {
        require(requests[_id].user == msg.sender, "Unauthorized: only creator");
        _;
    }

    constructor(){
        ac.grant("", msg.sender);
        ac.grant("", msg.sender);
    }

    function createRequest (
        address _user,
        address _token,
        uint256 _amount,
        RampType _rampType
    ) external onlyOperator returns (uint256) {
        rampRequestsCount++;

        RampRequest memory newRequest = RampRequest(
            rampRequestsCount,
            _user,
            _token,
            _amount,
            _rampType,
            Status.PENDING,
            block.timestamp
        );

        requests[rampRequestsCount] = newRequest;

        return rampRequestsCount;
    }

    function fundEscrow (uint256 _id) external {
        RampRequest memory request = requests[_id];

        require(request.id != 0, "Invalid request");
        require(request.status == Status.PENDING, "invalid action");
        require(request.rampType == RampType.CRYPTO_TO_FIAT, "Invalid action");
        
        _transfer(request.amount, address(this), requests[_id].token);

        requests[_id].status = Status.COMPLETED;
    }

    function releaseEscrow (uint _id) external onlyCreator(_id) {
        RampRequest memory request = requests[_id];
        require(request.status == Status.PENDING, "Invalid action");
        require(request.rampType == RampType.FIAT_TO_CRYPTO, "Invalid action");

        _transfer(request.amount, request.user, request.token);
    }

    
    function _transfer(uint256 _amount, address _to, address _token) internal {
        if(_token == address(0)){
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Transfer failed.");
        }
        else{
            bool success = IERC20(_token).transfer(_to, _amount);
            require(success, "Transfer failed");
        }
    }
}
