// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interfaces/IFolioMaster.sol";

contract FolioMasterFactory is Ownable {

    address private implementation;

    mapping(address => bool) private _folioCreated;
    mapping(address => bool) private _approvedModules;

    event FolioCreated(
        address folio,
        address[] tokens,
        uint256[] weights,
        address manager
    );

    constructor(
        address _implementation
    ) {
        implementation = _implementation;
    }

    /**
     * Creates a new folio contract.
     * @param tokens The tokens used in folio.
     * @param weights The weights of each token in folio.
     * @param manager The address of manager.
     * @param uniswap UniswapV2 router address.
     * @param folioModule Address of folioModule.
     * @param salt salt used for CREATE2.
     */
    function createFolio(
        address[] memory tokens,
        uint256[] memory weights,
        address manager,
        address uniswap,
        address folioModule,  
        bytes32 salt                                                                                                                                                                                                                                                                                                                                
    ) external {

        bytes memory initData = abi.encodeWithSelector(
            IFolioMaster.initialize.selector,
            tokens,
            weights,
            manager,
            address(this),
            uniswap,
            folioModule
        );
        address proxy = Clones.cloneDeterministic(implementation, salt);
        proxy.call(initData);
        _folioCreated[proxy] = true;
        emit FolioCreated(proxy, tokens, weights, manager);
    }

    /**
     * Method used to predict deployed address wit hgiven salt.
     * @param _salt Salt used for CREATE2.
     */
    function predictAddress(
        bytes32 _salt
    ) external view returns(address) {
        return Clones.predictDeterministicAddress(implementation, _salt);
    }

    /**
     * Method used to approve a module for use in the folio.
     * @param _module Address of the deployed module to approve.
     */
    function approveModule(
        address _module
    ) external onlyOwner {
        _approvedModules[_module] = true;
    }

    /**
     * Method which checks if teh folio was created from the factory itself.
     * @param folio Method which checks if teh folio was created from the factory itself.
     */
    function checkValidFolio(
        address folio
    ) external view returns(bool) {
        return _folioCreated[folio];
    }

    /**
     * Method which checks if the module was approved.
     * @param module Address of the module to check approval.
     */
    function checkApprovedModule(
        address module
    ) external view returns(bool) {
        return _approvedModules[module];
    }

}