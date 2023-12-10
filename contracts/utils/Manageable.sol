// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


contract Manageable {

    address private _manager;

    modifier onlyManager() {
        require(msg.sender == _manager, "ERR: NOT MANAGER");
        _;
    }

    function __Manageable_init(address manager_) internal {
        _manager = manager_;
    }

    function manager() public view returns(address) {
        return _manager;
    }
}