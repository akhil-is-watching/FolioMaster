// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


interface IFolioMasterFactory {

    function checkValidFolio(
        address folio,
        address[] calldata tokens,
        uint256[] calldata weights,
        address manager
    ) external view returns(bool);

    function checkApprovedModule(
        address module
    ) external view returns(bool);

}