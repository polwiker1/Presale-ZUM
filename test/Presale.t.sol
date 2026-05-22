//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/presale.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAggregator.sol";

contract PresaleTest is Test {
    Presale public presale;
    MockERC20 public zum;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockAggregator public feed;

    address public owner = address(this);
    address public buyer = address(0xBEEF);
    address public treasury = address(0xCAFE);

    uint256 public constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 public constant PRESALE_SUPPLY = 100_000e18;

    // USD6 prices
    uint256 public constant P1 = 60_000; // 0.06
    uint256 public constant P2 = 75_000; // 0.075
    uint256 public constant P3 = 90_000; // 0.09

    function setUp() public {
        zum = new MockERC20("ZUM", "ZUM", 18);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        feed = new MockAggregator(3_000e8); // 3000 USD with 8 decimals

        zum.mint(owner, TOTAL_SUPPLY);
        usdt.mint(buyer, 1_000_000e6);
        usdc.mint(buyer, 1_000_000e6);

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);

        // cap is overwritten in constructor to 33.33/33.33/33.34 distribution
        phases[0][0] = 0;
        phases[1][0] = 0;
        phases[2][0] = 0;

        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;

        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        zum.approve(predictedPresale, PRESALE_SUPPLY);
        presale = new Presale(
            address(zum),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            t3,
            phases
        );

        vm.prank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        vm.prank(buyer);
        usdc.approve(address(presale), type(uint256).max);
    }

    function testPhase1PriceWithUSDT() public {
        vm.warp(presale.startingTime() + 1);

        uint256 payAmount = 600e6; // 600 USDT
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), payAmount);

        uint256 expected = 10_000e18; // 600 / 0.06 = 10,000 ZUM
        assertEq(presale.userTokenBalance(buyer), expected);
        assertEq(presale.currentPhase(), 0);
    }

    function testMoveToPhase2ByTime() public {
        vm.warp(presale.startingTime() + 30 days + 1);

        uint256 payAmount = 750e6; // 750 USDT
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), payAmount);

        uint256 expected = 10_000e18; // 750 / 0.075 = 10,000 ZUM
        assertEq(presale.userTokenBalance(buyer), expected);
        assertEq(presale.currentPhase(), 1);
    }

    function testMoveToPhase2ByCap() public {
        vm.warp(presale.startingTime() + 1);

        // Fill phase 0 using repeated buys until cap-based transition happens.
        while (presale.currentPhase() == 0) {
            vm.prank(buyer);
            presale.buyWithStable(address(usdt), 1_000e6);
        }

        uint256 before = presale.userTokenBalance(buyer);
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 75e6);
        uint256 afterBal = presale.userTokenBalance(buyer);
        uint256 minted = afterBal - before;

        // 75 / 0.075 = 1000 ZUM in phase 2
        assertEq(minted, 1_000e18);
        assertEq(presale.currentPhase(), 1);
    }

    function testPauseBlocksStableBuy() public {
        vm.warp(presale.startingTime() + 1);
        presale.pause();

        vm.prank(buyer);
        vm.expectRevert();
        presale.buyWithStable(address(usdt), 100e6);
    }

    function testUnpauseEnablesStableBuyAgain() public {
        vm.warp(presale.startingTime() + 1);
        presale.pause();
        presale.unpause();

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 60e6); // 60 / 0.06 = 1000

        assertEq(presale.userTokenBalance(buyer), 1_000e18);
    }

    function testGetEtherPriceRevertsWhenPriceIsStale() public {
        vm.warp(presale.startingTime() + 3 days);

        // Force stale oracle update timestamp (> MAX_PRICE_AGE = 1 hour).
        feed.setStale(block.timestamp - 2 hours);

        vm.expectRevert("Price too old");
        presale.getEtherPrice();
    }
}
