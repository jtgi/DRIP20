pragma solidity ^0.8.0;

import "../../src/ERC20SlimStream.sol";

contract MockERC20SlimStream is ERC20SlimStream {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _emissionRatePerBlock
    ) ERC20SlimStream(_name, _symbol, _decimals, _emissionRatePerBlock) {}

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function startStreaming(address addr) external virtual {
        _startStreaming(addr);
    }

    function stopStreaming(address addr) external virtual {
        _stopStreaming(addr);
    }

    function burn(address from, uint256 value) external virtual {
        _burn(from, value);
    }
}
