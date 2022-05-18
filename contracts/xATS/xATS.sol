// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract xATS is ERC20, ReentrancyGuard {
    IERC20 public stakedToken;
    using SafeMath for uint256;

    constructor() ERC20("xFSB", "xFSB") {
        stakedToken = IERC20(0xb8b66ccfF15A7118aE01C4ca9E2dD241DD5289f6);
    }

    function stake(uint256 _amount) external nonReentrant returns (uint256) {
        uint256 ratio = 10 ** decimals();
        if (totalSupply() > 0 && stakedToken.balanceOf(address(this)) > 0) {
            ratio = totalSupply().mul(10** decimals()).div(stakedToken.balanceOf(address(this)));
        }
        uint256 xATSAmount = ratio.mul(_amount).div(10** decimals());
        stakedToken.transferFrom(_msgSender(), address(this), xATSAmount);
        _mint(_msgSender(), xATSAmount);
        return xATSAmount;
    } // end of stake function

    function unStake(uint256 _amount) external nonReentrant returns (uint256) {
        uint256 ratio = 10 ** decimals();
        if (totalSupply() > 0 && stakedToken.balanceOf(address(this)) > 0) {
            ratio = stakedToken.balanceOf(address(this)).mul(10** decimals()).div(totalSupply());
        }
        uint256 atSAmount = ratio.mul(_amount).div(10** decimals());
        _burn(_msgSender(), _amount);
        stakedToken.transfer(_msgSender(), atSAmount);
        return atSAmount;
    }

    /**
    * @dev Returns the number of decimals used to get its user representation.
    * For example, if `decimals` equals `2`, a balance of `505` tokens should
    * be displayed to a user as `5.05` (`505 / 10 ** 2`).
    *
    * Tokens usually opt for a value of 18, imitating the relationship between
    * Ether and Wei. This is the value {ERC20} uses, unless this function is
    * overridden;
    *
    * NOTE: This information is only used for _display_ purposes: it in
    * no way affects any of the arithmetic of the contract, including
    * {IERC20-balanceOf} and {IERC20-transfer}.
    */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}