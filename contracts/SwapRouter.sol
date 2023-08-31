//SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

import './interfaces/ISwapFactory.sol';
import './interfaces/ISwapRouter.sol';
import './interfaces/ISwapTokenFactory.sol';
import './interfaces/ISwapTokenTemplate.sol';
import './libraries/SwapLibrary.sol';
import './libraries/TransferHelper.sol';
import './libraries/SafeMath2.sol';
import './interfaces/IERC20.sol';
import './interfaces/ISwapPlatToken.sol';

contract SwapRouter is ISwapRouter {
    using SafeMath for uint;
    using SafeMath for uint256;

    address public immutable override factory;
    address public immutable tokenFactory;
    address public immutable dfil;
    address public superAdmin;
    address public platTokenSetter;
    address public feeTo;
    uint public feeRate = 8;
    uint public feeBase = 1000;
    IPlatToken public platToken;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'SwapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _superAdmin, address _dfil, address _tokenFactory, address _feeTo) public {
        factory = _factory;        
        superAdmin = _superAdmin;
        dfil = _dfil;
        tokenFactory = _tokenFactory;
        feeTo = _feeTo;
        platTokenSetter = _superAdmin;
    }

    function setPlatToken(address platToken_) external {
        require(msg.sender == platTokenSetter, "err");
        platToken = IPlatToken(platToken_);
    }

    // feeTo
    function feeToWithdraw(address token) external {
        require(msg.sender == feeTo, "err");
        TransferHelper.safeTransfer(
            token, feeTo, IERC20(token).balanceOf(address(this))
        );
    }

    // superAdmin
    function setFeeTo(address _feeTo) external {
        require(msg.sender == superAdmin, "err");
        feeTo = _feeTo;
    }

    function setFee(uint _feeRate) external {
        require(msg.sender == superAdmin, "err");
        feeRate =  _feeRate;
    }

    /**
     * 质押条件判断，并质押
     */ 
    function _stake(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    ) internal {
        if (tokenA == dfil && ISwapTokenFactory(tokenFactory).existsToken(tokenB)) {
            if (1 == ISwapTokenTemplate(tokenB).getStakeType()) {
                // 等比
                ISwapTokenTemplate(tokenB).stakeRecord(msg.sender, amountA.mul(ISwapTokenTemplate(tokenB).getStageTypeRate().mul(ISwapTokenTemplate(tokenB).getStageTypeBase())));
            } else if (2 == ISwapTokenTemplate(tokenB).getStakeType()) {
                // 等额
                ISwapTokenTemplate(tokenB).stakeRecord(msg.sender, amountB.mul(ISwapTokenTemplate(tokenB).getStageTypeRate().mul(ISwapTokenTemplate(tokenB).getStageTypeBase())));
            }

        } else if (tokenB == dfil && ISwapTokenFactory(tokenFactory).existsToken(tokenA)) {
            if (1 == ISwapTokenTemplate(tokenA).getStakeType()) {
                ISwapTokenTemplate(tokenA).stakeRecord(msg.sender, amountA.mul(ISwapTokenTemplate(tokenA).getStageTypeRate().mul(ISwapTokenTemplate(tokenA).getStageTypeBase())));
            } else if (2 == ISwapTokenTemplate(tokenA).getStakeType()) {
                ISwapTokenTemplate(tokenA).stakeRecord(msg.sender, amountB.mul(ISwapTokenTemplate(tokenA).getStageTypeRate().mul(ISwapTokenTemplate(tokenA).getStageTypeBase())));
            }
        }
    }

    /**
     * 解押条件判断，并解押
     */ 
    function _unStake(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint allLiquidity
    ) internal {
        if (tokenA == dfil && ISwapTokenFactory(tokenFactory).existsToken(tokenB)) {
            ISwapTokenTemplate(tokenB).unStakeRecord(msg.sender, ISwapTokenTemplate(tokenB).getStageRecords(msg.sender).mul(liquidity).div(allLiquidity));
        } else if (tokenB == dfil && ISwapTokenFactory(tokenFactory).existsToken(tokenA)) {
            ISwapTokenTemplate(tokenA).unStakeRecord(msg.sender, ISwapTokenTemplate(tokenA).getStageRecords(msg.sender).mul(liquidity).div(allLiquidity));
        }
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = SwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = SwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = SwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        _stake(tokenA, tokenB, amountA, amountB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISwapPair(pair).mint(to);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        uint allLiquidity = ISwapPair(pair).balanceOf(msg.sender);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ISwapPair(pair).burn(to);
        (address token0,) = SwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');

        _unStake(tokenA, tokenB, liquidity, allLiquidity);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        ISwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SwapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? SwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            ISwapPair(SwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        uint usePlatToken,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(2 == path.length, 'SwapRouter: ERROR_PATH');
        amounts = SwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        
        _swapFee(amounts[0], path[0], usePlatToken);

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        uint usePlatToken,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(2 == path.length, 'SwapRouter: ERROR_PATH');
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'SwapRouter: EXCESSIVE_INPUT_AMOUNT');

        _swapFee(amounts[0], path[0], usePlatToken);

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SwapLibrary.sortTokens(input, output);
            ISwapPair pair = ISwapPair(SwapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = SwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? SwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        uint usePlatToken,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        require(2 == path.length, 'SwapRouter: ERROR_PATH');
        _swapFee(amountIn, path[0], usePlatToken);

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function _swapFee(uint amount, address token, uint usePlatToken) internal {
        // fee
        uint fee = amount.mul(feeRate).div(feeBase);
        if (fee > 0) {
            if (address(0) != address(platToken) && 0 < usePlatToken) {
                platToken.deal(fee);
            } else {
                // 兼容白名单
                TransferHelper.safeTransferFrom(
                    token, msg.sender, address(this), fee
                );
            }
        }
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return SwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return SwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return SwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return SwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return SwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
