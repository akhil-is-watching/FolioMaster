// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./utils/Manageable.sol";
import "./interfaces/IFolioMasterFactory.sol";


contract FolioMaster is Initializable, Manageable {

    using SafeMath for uint256;

    // Struct containing folio info.
    struct FolioInfo {
        address[] tokens;
        uint256[] units;
        uint256 lastDepositShares;
        uint256 lastDepositTimestamp;
        uint256 totalFeeAccrued;
        uint256 totalFeeRate;
    }

    // Struct containing user info.
    struct UserInfo {
        uint256 shares;
        uint256 lastDepositShares;
        uint256 lastDepositTimestamp;
        uint256 totalFeeAccrued;
    }

    mapping(address => UserInfo) public userInfo;
    uint256 totalShares;        // Total shares the folio has issued.

    FolioInfo private folio;    // FolioInfo instance.
    IUniswapV2Router02 private uniswap; // UniswapV2 Router instance.

    address public factory;

    address public folioModule;

    // Initialization function.
    function initialize(
        address[] memory tokens,
        uint256[] memory units,
        address _manager,
        address _factory,
        address _uniswapAddress,
        address _folioModule 
    ) external initializer {
        __Manageable_init(_manager);
        factory = _factory;
        folio.tokens = tokens;
        folio.units = units;
        uniswap = IUniswapV2Router02(_uniswapAddress);
        folioModule = _folioModule;
    }

    /**
     * Deposit function for folio
     * @param data The data to pass for delegatecall deposit.
     */
    function deposit(
        bytes calldata data
    ) external {
        _delegateCall(folioModule, data);
    }

    /**
     * Withdraw function for folio
     * @param data The data to pass for delegatecall deposit.
     */
    function withdraw(
        bytes calldata data
    ) external {
        _delegateCall(folioModule, data);
    }

    /**
     * Returns the number of shares a user holds.
     * @param _user The address of user to check shares for.
     */
    function shares(address _user) public view returns(uint256) {
        UserInfo storage user = userInfo[_user];
        return user.shares;
    }

    /**
     * Returns the price of (N) units in terms of a token.
     * @param dToken The token used for purchase.
     * @param _shares Number of units to purchase.
     * @param paths Array of uniswap paths required for swap.
     * @return Total number of tokens needed for units.
     * @return Different composition of Total tokens.
     */
    function getPrice(
        address dToken,
        uint256 _shares,
        address[][] memory paths
    ) public view returns(uint256, uint256[] memory) {
        require(folio.tokens.length == paths.length, "ERR: INVALID PATH ARRAY");
        uint256 price = 0;
        uint256[] memory composition = new uint256[](paths.length);
        for(uint256 i=0; i<paths.length; i++) {
            address[] memory path = paths[i];
            uint256[] memory amountsIn = uniswap.getAmountsIn(folio.units[i].mul(_shares).div(1e18), path);
            require(path[0] == dToken && path[path.length-1] == folio.tokens[i], "ERR: INVALID PATH");
            uint256 amountIn = amountsIn[0];
            price = price.add(amountIn);
            composition[i] = amountIn;
        }
        return (price, composition);
    }

    /**
     * Function used for delegateCall to a approved module/logic contract.
     * @param _target The module address.
     * @param _data  The data to call on the module.
     */
    function delegateCall(
        address _target,
        bytes calldata _data
    ) external onlyManager returns(bytes memory){
        require(IFolioMasterFactory(factory).checkApprovedModule(_target), "ERR: NON AUTHORIZED MODULE");
        return _delegateCall(_target, _data);
    }

    /**
     * Internal private function used for delegateCall.
     * @param _target The target logic contract.
     * @param _data The data to pass in the call.
     */
    function _delegateCall(
        address _target,
        bytes calldata _data
    ) private returns(bytes memory){
        (bool success, bytes memory data) = _target.delegatecall(_data);
        require(success, "ERR: DELEGATECALL FAILED");
        return data;
    }
}