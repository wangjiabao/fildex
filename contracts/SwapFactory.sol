pragma solidity =0.5.16;

import './interfaces/ISwapFactory.sol';
import './interfaces/ITokenExists.sol';
import './interfaces/IRewardPool.sol';
import './SwapPair.sol';

contract SwapFactory is ISwapFactory {
    address public factoryAdmin;
    address public callPair;
    address public callPairSetter;
    address public tokenCheck;

    bytes32 public constant INIT_CODE_HASH = keccak256(abi.encodePacked(type(SwapPair).creationCode));

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _factoryAdmin, address _tokenCheck, address _callPairSetter) public {
        factoryAdmin = _factoryAdmin;
        tokenCheck = _tokenCheck;
        callPairSetter = _callPairSetter;
    }

    function getAllPairs() external view returns (address[] memory) {
        return allPairs;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(callPair != address(0), 'Swap: CAll_PAIR_ZERO_ADDRESS');
        require(tokenA != tokenB, 'Swap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Swap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Swap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(SwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        
        address rewardPool;
        if (ITokenExists(tokenCheck).existsToken(token0) || ITokenExists(tokenCheck).existsTopUnionToken(token0)) {
            rewardPool = token0;
            IRewardPool(rewardPool).setStake(pair);
        } else if (ITokenExists(tokenCheck).existsToken(token1) || ITokenExists(tokenCheck).existsTopUnionToken(token1)) {
            rewardPool = token1;
            IRewardPool(rewardPool).setStake(pair);
        }

        ISwapPair(pair).initialize(token0, token1, callPair, rewardPool);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // call pair setter
    function setCallPair(address _callPair) external {
        require(msg.sender == callPairSetter, 'UniswapV2: FORBIDDEN');
        callPair = _callPair;
    }

    function setCallPairSetter(address _callPairSetter) external {
        require(msg.sender == factoryAdmin, 'UniswapV2: FORBIDDEN');
        callPairSetter = _callPairSetter;
    }
}
