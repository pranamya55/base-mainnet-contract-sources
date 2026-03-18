// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./IZeroEx.sol";
import "@0x/contracts-utils/contracts/src/v06/LibBytesV06.sol";
import "@0x/contracts-zero-ex/contracts/src/errors/LibProxyRichErrors.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Coinbase proxy contract for 0x proxy
/// @dev A generic proxy contract which extracts a fee before delegation
contract ZeroExProxy is Ownable {
    using LibBytesV06 for bytes;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address private constant _ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant _NULL_ADDRESS = 0x0000000000000000000000000000000000000000;

    address payable private _beneficiary;
    address payable private _allowanceTarget;
    IZeroExV2 private _zeroEx;

    event BeneficiaryChanged(address indexed beneficiary);
    event AllowanceTargetChanged(address indexed allowanceTarget);
    event ZeroExChanged(address indexed zeroEx);

    /// @dev Construct this contract and specify a fee beneficiary, 0x proxy contract address, and allowance target
    constructor(
        IZeroExV2 zeroEx, 
        address payable allowanceTarget, 
        address payable beneficiary,
        address operator

    ) public {
        _zeroEx = zeroEx;
        _allowanceTarget = allowanceTarget;
        _beneficiary = beneficiary;

        // If operator is set, transfer ownership to operator
        // Otherwise it defaults to the deployer
        if (operator != address(0)) {
            transferOwnership(operator);
        }
    }

    /// @dev Fallback for just receiving ether.
    receive() external payable {}

    /// @dev Forwards calls to the zeroEx contract and extracts a fee based on provided arguments
    /// @param msgData The byte data representing a swap using the original ZeroEx contract. This is either recieved from the 0x API directly or we construct it in order to perform a Uniswap trade
    /// @param feeToken The ERC20 we wish to extract a user fee from. If this is ETH it should be the standard 0xeee ETH address
    /// @param inputToken The ERC20 the user is selling. If this is ETH it should be the standard 0xeee ETH address
    /// @param inputAmount The amount of _inputToken being sold
    /// @param outputToken The ERC20 the user is buying. If this is ETH it should be the standard 0xeee ETH address
    /// @param fee Fee amount collected and sent to the beneficiary
    function proxiedSwap(
        bytes calldata msgData,
        address feeToken,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 fee
    ) external payable returns (bytes memory) {
    return _proxiedSwap(msgData, feeToken, inputToken, inputAmount, outputToken, msg.sender, fee);
    }

    function proxiedSwapTo(
        bytes calldata msgData,
        address feeToken,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        address receiver,
        uint256 fee
    ) external payable returns (bytes memory) {
        return _proxiedSwap(msgData, feeToken, inputToken, inputAmount, outputToken, receiver, fee);
    }

    function _proxiedSwap(
        bytes calldata msgData,
        address feeToken,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        address receiver,
        uint256 fee
    ) internal returns (bytes memory) {
        _payFees(feeToken, fee);
        uint256 value = 0;
        if (inputToken == _ETH_ADDRESS) {
            if (feeToken == _ETH_ADDRESS) {
                require(msg.value == inputAmount.add(fee),"Insufficient value with fee");
            }
            else {
                require(msg.value == inputAmount, "Insufficient value");
            }
            value = inputAmount;
        }
        else {
            _sendERC20(IERC20(inputToken), msg.sender, address(this), inputAmount);
            uint256 allowedAmount = IERC20(inputToken).allowance(address(this), _allowanceTarget);
            if (allowedAmount < inputAmount) {
                IERC20(inputToken).safeIncreaseAllowance(_allowanceTarget, inputAmount.sub(allowedAmount));
            }
        }
        (bool success, bytes memory resultData) = address(_zeroEx).call{value: value}(msgData);
        if (!success) {
            _revertWithData(resultData);
        }
        if (outputToken == _ETH_ADDRESS) {
            if (address(this).balance > 0) {
                _sendETH(payable(receiver), address(this).balance);
            } else {
                _revertWithData(resultData);
            }
        } else {
            uint256 tokenBalance = IERC20(outputToken).balanceOf(address(this));
            if (tokenBalance > 0) {
                IERC20(outputToken).safeTransfer(receiver, tokenBalance);
            } else {
                _revertWithData(resultData);
            }
        }
        _returnWithData(resultData);
    }

    /// @dev Set a new 0x proxy contract address
    /// @param newZeroEx New 0x proxy address
    function setZeroEx(IZeroExV2 newZeroEx) public onlyOwner{
        require(address(newZeroEx) != _NULL_ADDRESS, "Invalid zeroEx address");
        _zeroEx = newZeroEx;
        emit ZeroExChanged(address(_zeroEx));
    }

    /// @dev Set a new new allowance target address 
    /// @param newAllowanceTarget New allowance target address
    function setAllowanceTarget(address payable newAllowanceTarget) public onlyOwner {
        require(newAllowanceTarget != _NULL_ADDRESS, "Invalid allowance target");
        _allowanceTarget = newAllowanceTarget;
        emit AllowanceTargetChanged(_allowanceTarget);
    }

    /// @dev Set a new beneficiary address 
    /// @param beneficiary New beneficiary target address
    function setBeneficiary(address payable beneficiary) public onlyOwner {
        require(beneficiary != _NULL_ADDRESS, "Invalid beneficiary");
        _beneficiary = beneficiary;
        emit BeneficiaryChanged(_beneficiary);
    }

    function getBeneficiary() public view returns(address) {
        return _beneficiary;
    }

    function getAllowanceTarget() public view returns(address){
        return _allowanceTarget;
    }

    function getZeroEx() public view returns(IZeroExV2) {
        return _zeroEx;
    }

    /// @dev Pay fee to beneficiary 
    /// @param token token address to pay fee in, can be ETH
    /// @param amount fee amount to pay
    function _payFees(address token, uint256 amount) private {
        if (token == _ETH_ADDRESS) {
            return _sendETH(_beneficiary, amount);
        }
        return _sendERC20(IERC20(token), msg.sender, _beneficiary, amount);
    }

    function _sendETH(address payable toAddress, uint256 amount) private {
        if (amount > 0) {
            (bool success,) = toAddress.call{ value: amount }("");
            require(success, "Unable to send ETH");
        }
    }

    function _sendERC20(IERC20 token, address fromAddress, address toAddress, uint256 amount) private {
        if (amount > 0) {
            token.safeTransferFrom(fromAddress, toAddress, amount);
        }
    }

    /// @dev Revert with arbitrary bytes.
    /// @param data Revert data.
    function _revertWithData(bytes memory data) private pure {
        assembly { revert(add(data, 32), mload(data)) }
    }

    /// @dev Return with arbitrary bytes.
    /// @param data Return data.
    function _returnWithData(bytes memory data) private pure {
        assembly { return(add(data, 32), mload(data)) }
    }
}