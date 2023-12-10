// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


interface IFolioMaster {

    event FolioInitialized(
        address[] tokens,
        uint256[] weights,
        address manager
    );

    function initialize(
        address[] memory tokens,
        uint256[] memory units,
        address _manager,
        address _factory,
        address _uniswapAddress,
        address _folioModule 
    ) external;


    function delegateCall(
        address _target,
        bytes calldata _data
    ) external;
}