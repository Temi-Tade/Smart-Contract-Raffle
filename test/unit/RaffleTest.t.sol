// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed recentWinner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // arrange
        vm.prank(PLAYER);
        // act / assert
        vm.expectRevert(Raffle.Raffle__SendMoreEthToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRevertsWhenEntranceFeeIsNotEnough() public {
        // arrange
        vm.prank(PLAYER);
        // act / assert
        vm.expectRevert(Raffle.Raffle__SendMoreEthToEnterRaffle.selector);
        raffle.enterRaffle{value: entranceFee - 0.001 ether}();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // arrange
        vm.prank(PLAYER);
        // act
        raffle.enterRaffle{value: entranceFee}();
        // assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        // arrange
        vm.prank(PLAYER);
        // act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        // assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // sets block.timestamp
        vm.roll(block.number + 1); // sets block number
        raffle.performUpkeep("");
        // act
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // assert
    }

    ///////////////////
    // CHECK UPKEEP //
    //////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // arrange
        vm.prank(PLAYER);
        vm.warp(block.timestamp + interval + 1); // sets block.timestamp
        vm.roll(block.number + 1); // sets block number
        // act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // sets block.timestamp
        vm.roll(block.number + 1); // sets block number
        raffle.performUpkeep("");
        // act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // assert
        assert(!upkeepNeeded);
    }

    // enoughtimehaspassed
    // params are good
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // vm.warp(block.timestamp + interval + 1);
        // vm.roll(block.number + 1);
        // raffle.performUpkeep("");
        // act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // assert
        assert(upkeepNeeded);
    }

    ///////////////////
    // PERFORM UPKEEP //
    //////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // act / assert
        raffle.performUpkeep(""); // it doesn't revert
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // act / assert
        uint256 currentBalance = raffle.getBalance();
        uint256 numPlayers = raffle.getNumberOfPlayers();
        Raffle.RaffleState currentRaffleState = raffle.getRaffleState();
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, currentRaffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // what if we need to get data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        // arrange

        // act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    //////////////////////////
    // FULFILL RANDOM WORDS //
    //////////////////////////
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerfomUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        skipFork
    {
        // arrange / act / assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksWinnerAndSendsMoney() public raffleEntered skipFork {
        // arrange
        uint256 additionalEntrants = 3; // 4 players in total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // act
        // get a req id
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
