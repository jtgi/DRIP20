// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20SlimStream {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    // uint256 public totalSupply;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                            STREAM STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public emissionRatePerBlock;
    mapping(address => uint256) private _balance;
    mapping(address => uint256) private _accrualStartBlock;

    uint256 private _currAccrued;
    uint256 private _currEmissionBlockNum;
    uint256 private _currNumAccruers;

    // no need to implement stop emissions in this base contract
    // this contract is only to specify a streaming erc20 token
    // implementation details of how to stop emissions or maybe try to
    // enforce a max supply is up to the implementing contract
    // similar to how erc20 doesnt enforce a max supply, its up to the implementing contract
    // we made this for mirakai, which has burning of scrolls, so emission will
    // naturally stop as theyre all burned.
    // you could probably write some cool logic to stop streaming to wallets since
    // setting to 0 gives you a gas refund
    uint256 private _emissionStopBlockNum;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function totalSupply() public view returns (uint256) {
        return
            _currAccrued +
            (block.number - _currEmissionBlockNum) *
            emissionRatePerBlock *
            _currNumAccruers;
    }

    function y(address addr) external view returns (uint256) {
        return _accrualStartBlock[addr];
    }

    //'a','a',18,1000000000000000000,1000
    //0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678 -- 1005600
    //0x617F2E2fD72FD9D5503197092aC168c91465E7f2 -- 2100
    // 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB - 200
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _emissionRatePerBlock
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        emissionRatePerBlock = _emissionRatePerBlock;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount)
        public
        virtual
        returns (bool)
    {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(to != address(0), "ERC20: transfer to the zero address");

        _balance[from] = balanceOf(from) - amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _balance[to] += amount;
        }

        if (_accrualStartBlock[from] != 0) {
            _accrualStartBlock[from] = block.number;
        }

        emit Transfer(from, to, amount);
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        _transfer(from, to, amount);

        return true;
    }

    // also stop accruing
    function _startStreaming(address addr) internal virtual {
        // require the addr isnt already streaming to prevent tampering with max supply
        // ie keep increasing accruers
        _currAccrued = totalSupply();
        _currEmissionBlockNum = block.number;
        _currNumAccruers++;
        _accrualStartBlock[addr] = block.number;
    }

    function _stopStreaming(address addr) internal virtual {
        // require the addr isnt already streaming to prevent tampering with max supply
        // ie keep increasing accruers
        _balance[addr] = balanceOf(addr);
        _currAccrued = totalSupply();
        _currEmissionBlockNum = block.number;
        _currNumAccruers--;
        _accrualStartBlock[addr] = 0;
    }

    function balanceOf(address addr) public view returns (uint256) {
        if (_accrualStartBlock[addr] == 0) {
            return _balance[addr];
        }

        return
            ((block.number - _accrualStartBlock[addr]) * emissionRatePerBlock) +
            _balance[addr];
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(
                recoveredAddress != address(0) && recoveredAddress == owner,
                "INVALID_SIGNER"
            );

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    // function mint(uint256 amount) external {
    //     _mint(msg.sender, amount);
    // }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        _currAccrued += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _balance[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        // have to update supply before burning
        _currAccrued = totalSupply();
        _currEmissionBlockNum = block.number;
        //stop streaming if burn
        _balance[from] = balanceOf(from) - amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            _currAccrued -= amount;
        }

        if (_accrualStartBlock[from] != 0) {
            _accrualStartBlock[from] = block.number;
        }

        emit Transfer(from, address(0), amount);
    }
}
