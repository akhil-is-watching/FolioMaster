// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC6551Account {

    receive() external payable;

    function token()
        external
        view
        returns (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        );

    function owner() external view returns (address);

}