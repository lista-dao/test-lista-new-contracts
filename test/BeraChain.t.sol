/**
 * 
 * 
 * 
 */
// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeraChainVaultAdapter} from "src/contracts/BeraChainVaultAdapter.sol";
import {NonTransferableLpERC20} from "src/contracts/token/NonTransferableLpERC20.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Helper} from "test/util/Helper.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";


contract BeraChainTest is Test, Helper {
    IERC20 public BTCB = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
    BeraChainVaultAdapter public vaultAdapter;
    NonTransferableLpERC20 public lpToken;

    address aProxyAdminOwner = makeAddress("proxyAdminOwner");
    address aAdmin = makeAddress("admin");
    address aManager = makeAddress("manager");
    address aPauser = makeAddress("pauser");
    address aBot = makeAddress("bot");
    address user1 = makeAddress("user1");
    address user2 = makeAddress("user2");
    address aBotWithdrawReceiver = makeAddress("botWithdrawReceiver");
    uint256 depositEndTime;

    function setUp() public {
        vm.createSelectFork("bsc-main");
        deal(address(BTCB), user1, 1000 ether);
        deal(address(BTCB), user2, 1000 ether);

        depositEndTime = vm.getBlockTimestamp() + uint256(2 weeks);
        deployAndInit();
        assertEq(depositEndTime, vaultAdapter.depositEndTime());
        assertEq(aBotWithdrawReceiver, vaultAdapter.botWithdrawReceiver());
        assertTrue(vaultAdapter.hasRole(vaultAdapter.BOT(), aBot));
        assertTrue(vaultAdapter.hasRole(vaultAdapter.PAUSER(), aPauser));
        assertTrue(vaultAdapter.hasRole(vaultAdapter.MANAGER(), aManager));
        assertTrue(vaultAdapter.hasRole(vaultAdapter.DEFAULT_ADMIN_ROLE(), aAdmin));
    }

    // 测试lpToken 不可转移性
    function test_transfer() public {
        vm.prank(address(this));
        lpToken.addMinter(address(vaultAdapter));

        vm.prank(address(vaultAdapter));
        lpToken.mint(user1, 1000 ether);
        assertEq(1000 ether, lpToken.balanceOf(user1));

        // 直接转账
        vm.prank(user1);
        vm.expectRevert(bytes("Not transferable"));
        lpToken.transfer(user2, 100 ether);

        // 代理转账
        vm.prank(user1);
        vm.expectRevert(bytes("Not transferable"));
        lpToken.approve(user2, 100 ether);

        vm.expectRevert(bytes("Not transferable"));
        lpToken.transferFrom(user1, user2, 100 ether);

    }

    // 测试只有minter可以mint，也就是只有vaultAdapter可以mint
    function test_mint() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Minter: not allowed"));
        lpToken.mint(user1, 1000 ether);

        vm.prank(address(vaultAdapter));
        vm.expectRevert(bytes("Minter: not allowed"));
        lpToken.mint(user1, 1000 ether);

        // 添加权限, 因为lp合约是测试用例去部署的，所以owner就是测试用例地址
        vm.prank(address(this));
        lpToken.addMinter(address(vaultAdapter));

        vm.prank(address(vaultAdapter));
        lpToken.mint(user1, 1000 ether);
        assertEq(1000 ether, lpToken.balanceOf(user1));

        // 收回权利，无法mint
        vm.prank(address(this));
        lpToken.removeMinter(address(vaultAdapter));

        vm.expectRevert(bytes("Minter: not allowed"));
        vm.prank(address(vaultAdapter));
        lpToken.mint(user1, 1000 ether);
    }

    // 不变量， vault的totalSupply应该等于lpToken的totalSupply
    function test_deposit_beforeEndTime() public {
        // 设置mint
        lpToken.addMinter(address(vaultAdapter)); 
        uint256 lpTotalSupply = lpToken.totalSupply();

        vm.startPrank(user1);
        BTCB.approve(address(vaultAdapter), 1000 ether);
        vaultAdapter.deposit(100 ether);
        assertEq(100 ether, vaultAdapter.getUserLpBalance(user1));
        assertEq(lpTotalSupply + 100 ether, lpToken.totalSupply());
        vaultAdapter.deposit(100 ether);
        assertEq(200 ether, vaultAdapter.getUserLpBalance(user1));
        assertEq(lpTotalSupply + 200 ether, lpToken.totalSupply());
        vm.stopPrank();

        vm.startPrank(user2);
        BTCB.approve(address(vaultAdapter), 1000 ether);
        vaultAdapter.deposit(100 ether);
        assertEq(100 ether, vaultAdapter.getUserLpBalance(user2));
        assertEq(lpTotalSupply + 300 ether, lpToken.totalSupply());
        vaultAdapter.deposit(100 ether);
        assertEq(200 ether, vaultAdapter.getUserLpBalance(user2));
        assertEq(lpTotalSupply + 400 ether, lpToken.totalSupply());
        vm.stopPrank();
    }

    function test_deposit_afterEndTime() public {
        // 设置mint
        lpToken.addMinter(address(vaultAdapter)); 

        skip(3 weeks);
        require(vm.getBlockTimestamp() >= depositEndTime, "not reach depositEndTime");

        // 无法存入
        vm.prank(user1);
        vm.expectRevert(bytes("deposit closed"));
        vaultAdapter.deposit(100 ether);

        // 重新设置depositEndTime
        depositEndTime = vm.getBlockTimestamp() + uint256(2 weeks);

        vm.prank(aManager);
        vm.expectRevert();
        vaultAdapter.setDepositEndTime(depositEndTime);
        vm.prank(address(aAdmin));
        vaultAdapter.setDepositEndTime(depositEndTime); 
        
        // 可以存入
        vm.startPrank(user1);
        BTCB.approve(address(vaultAdapter), 100 ether);
        vaultAdapter.deposit(100 ether);
        vm.stopPrank();

        assertEq(100 ether, vaultAdapter.getUserLpBalance(user1));
    }

    function test_bot_withdraw() public {
        // 设置mint
        lpToken.addMinter(address(vaultAdapter)); 

        uint256 tokenBalance = BTCB.balanceOf(address(vaultAdapter));
        vm.prank(aBot);
        vm.expectRevert(bytes("insufficient balance"));
        vaultAdapter.botWithdraw(tokenBalance + 100 ether);

        vm.startPrank(user1);
        BTCB.approve(address(vaultAdapter), 1000 ether);
        vaultAdapter.deposit(100 ether);
        vm.stopPrank();
        tokenBalance = BTCB.balanceOf(address(vaultAdapter));

        uint256 botTokenBalance = BTCB.balanceOf(aBotWithdrawReceiver);
        // 只有bot可以调用
        vm.prank(aManager);
        vm.expectRevert();
        vaultAdapter.botWithdraw(tokenBalance);

        vm.prank(aBot);
        vaultAdapter.botWithdraw(tokenBalance);
        assertEq(botTokenBalance + tokenBalance, BTCB.balanceOf(aBotWithdrawReceiver));
    }

    function test_manager_withdraw() public {
        // 设置mint
        lpToken.addMinter(address(vaultAdapter)); 

        uint256 tokenBalance = BTCB.balanceOf(address(vaultAdapter));
        vm.prank(aManager);
        vm.expectRevert(bytes("insufficient balance"));
        vaultAdapter.managerWithdraw(user2, tokenBalance + 100 ether);

        vm.startPrank(user1);
        BTCB.approve(address(vaultAdapter), 1000 ether);
        vaultAdapter.deposit(100 ether);
        vm.stopPrank();

        tokenBalance = BTCB.balanceOf(address(vaultAdapter));
        // 只有manager可以调用
        vm.prank(aBot);
        vm.expectRevert();
        vaultAdapter.managerWithdraw(user1, tokenBalance);

        vm.prank(aManager);
        vaultAdapter.managerWithdraw(user2, tokenBalance);
        assertEq(100 ether + 1000 ether, BTCB.balanceOf(user2)); 
    }

    function test_pause() public {
        // 设置mint
        lpToken.addMinter(address(vaultAdapter)); 

        vm.startPrank(user1);
        BTCB.approve(address(vaultAdapter), 1000 ether);
        // 未暂停
        vaultAdapter.deposit(100 ether);
        vm.stopPrank();

        vm.prank(aPauser);
        vaultAdapter.pause();
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vaultAdapter.deposit(100 ether);
        vm.prank(aBot);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vaultAdapter.botWithdraw(100 ether);
        vm.prank(aManager);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vaultAdapter.managerWithdraw(user1, 100 ether);
        
        // 由于admin基本上是给了timeLock合约，所以接触暂停我们一般给manager
        vm.prank(aPauser);
        vm.expectRevert();
        vaultAdapter.unpause();
        vm.prank(aManager);
        vaultAdapter.unpause();
        vm.startPrank(user1);
        vaultAdapter.deposit(100 ether);
        vm.stopPrank();

        vm.prank(aBot);
        vaultAdapter.botWithdraw(50 ether);
        vm.prank(aManager);
        vaultAdapter.managerWithdraw(user1, 50 ether);
    }

    function deployAndInit() private {
        TransparentUpgradeableProxy proxy0 = new TransparentUpgradeableProxy(
            address(new NonTransferableLpERC20()),
            aProxyAdminOwner,
            abi.encodeWithSignature("initialize(string,string)", "TestToken", "TEST")
        );

        lpToken = NonTransferableLpERC20(payable(address(proxy0)));

        BeraChainVaultAdapter impl = new BeraChainVaultAdapter();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(aProxyAdminOwner),
            abi.encodeWithSignature("initialize(address,address,address,address,address,address,address,uint256)", 
                aAdmin, aManager, aPauser, aBot, address(BTCB), address(lpToken), aBotWithdrawReceiver, depositEndTime)
        );
        vaultAdapter = BeraChainVaultAdapter(address(proxy));
    }
}