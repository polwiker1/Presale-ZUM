//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable, Pausable {
    using SafeERC20 for IERC20;

    address public saleTokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    address public datafeedaddress;

    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 public currentPhase;
    uint256 public totalSold;
    uint256 public constant MAX_PRICE_AGE = 1 hours;

    mapping(address => uint256) public userTokenBalance;
    mapping(address => bool) public isBlackListed;

    event TokenBuy(address user, uint256 amountPaid);

    constructor(
        address saleTokenAddress_,
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        address datafeedaddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        saleTokenAddress = saleTokenAddress_;
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        datafeedaddress = datafeedaddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(endingTime > startingTime, "Ending time must be greater than starting time");
        require(phases[0].length >= 3 && phases[1].length >= 3 && phases[2].length >= 3, "Invalid phases");
        require(phases[0][1] > 0 && phases[1][1] > 0 && phases[2][1] > 0, "Invalid phase price");

        // phases[i] = [capAcumulado, priceUsd6, endTime]
        uint256 phaseAmount = maxSellingAmount / 3;
        uint256 cap0 = phaseAmount;
        uint256 cap1 = phaseAmount * 2;
        uint256 cap2 = maxSellingAmount;

        phases[0][0] = cap0;
        phases[1][0] = cap1;
        phases[2][0] = cap2;

        IERC20(saleTokenAddress).safeTransferFrom(msg.sender, address(this), maxSellingAmount);
    }

    function blackList(address user_) external onlyOwner {
        isBlackListed[user_] = true;
    }

    function removeBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = false;
    }

    function checksCurrentPhase(uint256 amount_) private {
        while (currentPhase < 3) {
            bool withinCap = totalSold + amount_ <= phases[currentPhase][0];
            bool withinTime = block.timestamp <= phases[currentPhase][2];

            if (withinCap && withinTime) {
                return;
            }

            currentPhase++;
        }

        revert("No active phase");
    }

    function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external whenNotPaused {
        require(!isBlackListed[msg.sender], "You are blacklisted");
        require(block.timestamp > startingTime, "Presale has not started yet");
        require(block.timestamp <= endingTime, "Presale has ended");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Invalid token address");

        checksCurrentPhase(0);

        uint256 phaseAtPricing = currentPhase;
        uint256 phasePriceUsd6 = phases[phaseAtPricing][1];
        uint8 stableDecimals = IERC20Metadata(tokenUsedToBuy_).decimals();
        require(stableDecimals <= 18, "Unsupported token decimals");

        uint256 stableAmount18 = amount_ * (10 ** (18 - stableDecimals));
        uint256 tokenAmountToReceive = stableAmount18 * 1e6 / phasePriceUsd6;

        checksCurrentPhase(tokenAmountToReceive);
        if (currentPhase != phaseAtPricing) {
            phasePriceUsd6 = phases[currentPhase][1];
            tokenAmountToReceive = stableAmount18 * 1e6 / phasePriceUsd6;
            checksCurrentPhase(tokenAmountToReceive);
        }

        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Exceeds maximum selling amount");

        userTokenBalance[msg.sender] += tokenAmountToReceive;
        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);

        emit TokenBuy(msg.sender, amount_);
    }

    function buyWithEth() external payable whenNotPaused {
        require(!isBlackListed[msg.sender], "You are blacklisted");
        require(block.timestamp > startingTime, "Presale has not started yet");
        require(block.timestamp <= endingTime, "Presale has ended");

        checksCurrentPhase(0);

        uint256 usdValue = (msg.value * getEtherPrice()) / 1e18;
        uint256 phaseAtPricing = currentPhase;
        uint256 phasePriceUsd6 = phases[phaseAtPricing][1];
        uint256 tokenAmountToReceive = usdValue * 1e6 / phasePriceUsd6;

        checksCurrentPhase(tokenAmountToReceive);
        if (currentPhase != phaseAtPricing) {
            phasePriceUsd6 = phases[currentPhase][1];
            tokenAmountToReceive = usdValue * 1e6 / phasePriceUsd6;
            checksCurrentPhase(tokenAmountToReceive);
        }

        totalSold += tokenAmountToReceive;
        userTokenBalance[msg.sender] += tokenAmountToReceive;

        (bool success,) = fundsReceiverAddress.call{value: msg.value}("");
        require(success, "Transfer failed.");

        emit TokenBuy(msg.sender, msg.value);
    }

    function claim() external {
        require(block.timestamp > endingTime, "Presale has not ended yet");

        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];

        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getEtherPrice() public view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) =
            IAggregator(datafeedaddress).latestRoundData();

        require(price > 0, "Invalid ETH price");
        require(answeredInRound >= roundId, "Stale round");
        require(updatedAt > 0, "Round not complete");
        require(block.timestamp - updatedAt <= MAX_PRICE_AGE, "Price too old");

        return uint256(price) * (10 ** 10);
    }

    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyEthWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
