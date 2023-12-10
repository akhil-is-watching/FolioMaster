// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract FolioMasterModule {

    using SafeERC20 for IERC20;
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
        bool initialized;
    }

    mapping(address => UserInfo) public userInfo;
    uint256 totalShares;        // Total shares the folio has issued.

    FolioInfo private folio;    // FolioInfo instance.
    IUniswapV2Router02 private uniswap;     // UniswapV2 Router instance.

    address public factory;

    /**
     * It updates the fee for the lastDepositedUser and totalFeeAccrued for the folio.
     */
    modifier updateFee(address _user) {
        UserInfo storage user = userInfo[_user];
        uint256 userFeeAccrued = user.lastDepositShares.mul(block.timestamp - user.lastDepositTimestamp).mul(folio.totalFeeRate).div(1e20);
        user.totalFeeAccrued = user.totalFeeAccrued.add(userFeeAccrued);
        user.lastDepositTimestamp = block.timestamp;

        uint256 folioFeeAccrued = folio.lastDepositShares.mul(block.timestamp - folio.lastDepositTimestamp).mul(folio.totalFeeRate).div(1e20);
        folio.totalFeeAccrued = folio.totalFeeAccrued.add(folioFeeAccrued);    
        folio.lastDepositTimestamp = block.timestamp;
        _;
    }

    // Initialization function.
    function initialize(
        address[] memory tokens,
        uint256[] memory units,
        address _factory,
        address _uniswapAddress,
        uint256 totalFeeRate
    ) external {
        folio.tokens = tokens;
        folio.units = units;
        folio.totalFeeRate = totalFeeRate;
        factory = _factory;
        uniswap = IUniswapV2Router02(_uniswapAddress);
    }

    /**
     * Deposit function for folio
     * @param _user The user you want to deposit for.
     * @param _token The token used to buy assets.
     * @param _paths The buy paths used for swaps.
     * @param _shares Number shares you want to buy.
     */
    function deposit(
        address _user,
        address _token,
        address[][] memory _paths,
        uint256 _shares
    ) external updateFee(_user) {
        (uint256 amountRequired, uint256[] memory composition) = getPrice(_token, _shares, _paths);
        IERC20(_token).safeTransferFrom(_user, address(this), amountRequired);
        _swapToConstituents(_paths, composition);
        _deposit(_user, _shares);
    }

    /**
     * Withdraw function for folio
     * @param _user The user you want to withdraw for.
     * @param _token The token used to buy assets.
     * @param _paths The sell paths used for swaps.
     * @param _shares Number shares you want to sell.
     */
    function withdraw(
        address _user,
        address _token,
        address[][] memory _paths,
        uint256 _shares
    ) external updateFee(_user) {
        UserInfo storage user = userInfo[_user];
        require(_paths.length == folio.tokens.length, "ERR: INVALID PATH ARRAY");

        uint256[] memory composition = new uint256[](_paths.length);
        uint256 tokensWithdrawn = 0;
        uint256 availableShares = _shares.sub(user.totalFeeAccrued);
        // _shares = _shares.sub(user.totalFeeAccrued);
        for(uint256 i=0; i<_paths.length; i++) {
            uint256 tokensToSwap = availableShares.mul(folio.units[i]).div(1e18);
            composition[i] = tokensToSwap;
            uint256[] memory swappedTokenAmounts = uniswap.getAmountsOut(tokensToSwap, _paths[i]);
            uint256 swappedTokenAmount = swappedTokenAmounts[swappedTokenAmounts.length - 1];
            tokensWithdrawn = tokensWithdrawn.add(swappedTokenAmount);
        }

        _swapToConstituents(_paths, composition);
        IERC20(_token).safeTransfer(_user, tokensWithdrawn);
        _withdraw(_user, _shares);
        user.totalFeeAccrued = 0;
    }

    /**
     * Rebalance function for folio.
     * @param tokenA The token from which units to be transferred from.
     * @param tokenB The token from which units to be added to.
     * @param units Number of units to transfer.
     * @param path uniswap path from @param tokenA to @param tokenB
     */
    function rebalance(
        address tokenA, 
        address tokenB, 
        uint256 units,
        address[] memory path
    ) external {
        (uint256 indexA, bool ftA) = checkExistence(tokenA, folio.tokens);
        (uint256 indexB, bool ftB) = checkExistence(tokenB, folio.tokens);
        require(ftA && ftB, "ERR: TOKENS NOT FOUND");
        require(folio.units[indexA] >= units, "ERR: INSUFFICIENT UNITS TO TRANSFER");
        uint256 tokenABalance = IERC20(tokenA).balanceOf(address(this));
        uint256 shareValue = totalShares.mul(folio.units[indexA]).div(1e18);
        uint256 tokensToSwap = tokenABalance > shareValue ? tokenABalance : shareValue;
        uint256[] memory expectedSwapAmounts = uniswap.getAmountsOut(tokensToSwap, path);
        _swap(tokensToSwap, path);
        folio.units[indexA] = folio.units[indexA].sub(units);
        folio.units[indexB] = folio.units[indexB].add(expectedSwapAmounts[expectedSwapAmounts.length - 1].div(totalShares));
    }

    /**
     * Method for withdrawing managerFee
     * @param manager Address of manager.
     * @param _token the token you want to withdraw as.
     * @param _paths The array of sell paths.
     */
    function withdrawFee(
        address manager,
        address _token,
        address[][] memory _paths
    ) external {
        uint256 feeAccrued = getTotalFeeAccrued();
        uint256[] memory composition = new uint256[](_paths.length);
        uint256 tokensWithdrawn = 0;
        for(uint256 i=0; i<_paths.length; i++) {
            uint256 tokensToSwap = feeAccrued.mul(folio.units[i]).div(1e18);
            uint256[] memory swappedTokenAmounts = uniswap.getAmountsOut(tokensToSwap, _paths[i]);
            uint256 swappedTokenAmount = swappedTokenAmounts[swappedTokenAmounts.length - 1];
            composition[i] = tokensToSwap;
            tokensWithdrawn = tokensWithdrawn.add(swappedTokenAmount);
        }

        _swapToConstituents(_paths, composition);
        IERC20(_token).safeTransfer(manager, tokensWithdrawn);
        
        folio.lastDepositShares = totalShares;
        folio.lastDepositTimestamp = block.timestamp;
        folio.totalFeeAccrued = 0;
    }

    /**
     * Get fee accrued for a user.
     * @param _user Address of user.
     */
    function getFeeAccrued(address _user) public view returns(uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 feeAccrued = user.lastDepositShares.mul(block.timestamp - user.lastDepositTimestamp).mul(folio.totalFeeRate).div(1e20);
        return user.totalFeeAccrued.add(feeAccrued);
    }

    /**
     * Get the total fee accrued for manager to withdraw.
     */
    function getTotalFeeAccrued() public view returns(uint256) {
        uint256 folioFeeAccrued = folio.lastDepositShares.mul(block.timestamp - folio.lastDepositTimestamp).mul(folio.totalFeeRate).div(1e20);
        return folio.totalFeeAccrued.add(folioFeeAccrued);
    }

    /**
     * Shares a user holds
     * @param _user address of user to check shares for.
     */
    function shares(address _user) public view returns(uint256) {
        UserInfo storage user = userInfo[_user];
        return user.shares.sub(user.totalFeeAccrued);
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
     * Internal helper function for incrementing shares
     * @param _user Address of user to update the shares for.
     * @param _shares Number of shares to deposit.
     */
    function _deposit(address _user, uint256 _shares) private {
        UserInfo storage user = userInfo[_user];
        user.shares = user.shares.add(_shares);
        totalShares = totalShares.add(_shares);

        user.lastDepositShares = user.shares;
        user.lastDepositTimestamp = block.timestamp;

        folio.lastDepositShares = totalShares;
        folio.lastDepositTimestamp = block.timestamp;
    }

    /**
     * Internal helper function for decrementing shares
     * @param _user Address of user to update the shares for.
     * @param _shares Number of shares to withdraw.
     */
    function _withdraw(address _user, uint256 _shares) private {
        UserInfo storage user = userInfo[_user];
        require(user.shares >= _shares, "ERR: INSUFFICIENT SHARES");
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);

        user.lastDepositShares = user.shares;
        user.lastDepositTimestamp = block.timestamp;

        folio.lastDepositShares = totalShares;
        folio.lastDepositTimestamp = block.timestamp;
    }

    /**
     * Internal helper function which swaps a single token into multiple tokens given oath and composition.
     * @param _paths Array of buyPaths for each constituent token.
     * @param _compositon Array of token amounts to swap.
     */
    function _swapToConstituents(
        address[][] memory _paths,
        uint256[] memory _compositon
    ) internal {
        for(uint256 i=0; i<_paths.length; i++) {
            _swap(_compositon[i], _paths[i]);
        }
    }

    /**
     * UniswapV2 Helper Function
     * @param _amountIn Amount of token you want to swap.
     * @param _path The path for uniswap.
     */
    function _swap(
        uint256 _amountIn,
        address[] memory _path
    ) private {
        IERC20(_path[0]).approve(address(uniswap), _amountIn);
        uniswap.swapExactTokensForTokens(
            _amountIn,
            0,
            _path,
            address(this),
            block.timestamp + 60
        );
    }

    /**
     * Checks the existence of a token address in an array of addresses.
     * @param token The token to check existence for.
     * @param tokens THe array of tokens to chek inside.
     * @return Index of the address in array.
     * @return Result of find in array.
     */
    function checkExistence(address token, address[] memory tokens) private pure returns(uint256, bool) {
        for(uint256 i=0; i<tokens.length; i++) {
            if(token == tokens[i]) {
                return(i, true);
            }
        }
        return(tokens.length, false);
    }
}