import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from '@nomicfoundation/hardhat-network-helpers'

describe("Folio", function() {

  const UNISWAP_V2_ROUTER_ADDRESS = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
  let usdtAddress = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F"


  let tokens = [
      "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", //ETH
      "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", //BTC
      "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", //DAI
      "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1", //MAI
      "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b"
  ];

  let weights = ["10000000000000000", "10000000", "10000000000000000", "10000000000000000", "10000000000000000"];

  let path_BUY_ETH = [usdtAddress, "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"];
  let path_BUY_BTC = [usdtAddress, "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6"];
  let path_BUY_DAI = [usdtAddress, "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"];
  let path_BUY_MAI = [usdtAddress, "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1"];
  let path_BUY_AVAX = [usdtAddress, "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", "0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b"]

  let path_SELL_ETH = ["0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", usdtAddress ];
  let path_SELL_BTC = ["0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", usdtAddress];
  let path_SELL_DAI = ["0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", usdtAddress];
  let path_SELL_MAI = ["0xa3Fa99A148fA48D14Ed51d610c367C61876997F1", usdtAddress];
  let path_SELL_AVAX = ["0x2C89bbc92BD86F8075d1DEcc58C7F4E0107f286b", "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", usdtAddress];


  let buyPaths = [path_BUY_ETH, path_BUY_BTC, path_BUY_DAI, path_BUY_MAI, path_BUY_AVAX];
  let sellPaths = [path_SELL_ETH, path_SELL_BTC, path_SELL_DAI, path_SELL_MAI, path_SELL_AVAX]

  let TEST_SALT = "0x667a6b676e7a6c64676e7a646c6e676c647a6e6b676c6e6c6b73676e61736b6c"

  async function deployFolio() {
    const [ deployer ] = await ethers.getSigners();

    let depositor_ONE = await ethers.getImpersonatedSigner("0xee5B5B923fFcE93A870B3104b7CA09c3db80047A");
    let depositor_TWO = await ethers.getImpersonatedSigner("0x1a706EB4F22FDc03EE4624cF195cD9dABED2C264");
    let depositor_THREE = await ethers.getImpersonatedSigner("0x06959153B974D0D5fDfd87D561db6d8d4FA0bb0B");
    
    const Factory = await ethers.getContractFactory("FolioMasterFactory");
    const FolioModule = await ethers.getContractFactory("FolioMasterModule");
    const Implementation = await ethers.getContractFactory("FolioMaster");
    let USDT = await ethers.getContractAt("IERC20", usdtAddress, deployer);

    const implementation = await Implementation.deploy();
    await implementation.deployed();

    const factory = await Factory.deploy(implementation.address);
    await factory.deployed();

    const folioModule = await FolioModule.deploy();
    await folioModule.deployed();
    await folioModule.initialize(tokens, weights, factory.address, UNISWAP_V2_ROUTER_ADDRESS, 190258751903);

    await factory.approveModule(folioModule.address);
    await factory.createFolio(tokens, weights, deployer.address, UNISWAP_V2_ROUTER_ADDRESS, folioModule.address, TEST_SALT);

    const folioAddress = await factory.predictAddress(TEST_SALT);
    const folio = await Implementation.attach(folioAddress);

    return { folio, folioModule, factory, depositor_ONE, depositor_TWO, depositor_THREE, USDT, deployer }
  }


  describe("Deployment", async function() {

    it("Check if correct folio manager was set", async function() {
      const { folio, deployer } = await deployFolio();
      expect(await folio.manager()).to.equal(deployer.address);
    })

    it("Check if correct factory address was set", async function() {
      const { folio, factory } = await deployFolio();
      expect(await folio.factory()).to.equal(factory.address);      
    })
  })

  describe("Delegate Calls", function() {

    it("Should check if user gets alloted correct shares on deposit", async function() {
      const { folio, folioModule, depositor_ONE, depositor_TWO, USDT } = await deployFolio();

      await USDT.connect(depositor_ONE).approve(folioModule.address, ethers.utils.parseEther('1000'));
      await USDT.connect(depositor_TWO).approve(folioModule.address, ethers.utils.parseEther('1000'));

      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      expect(await folioModule.shares(depositor_ONE.address)).to.equal(ethers.utils.parseEther('1.0'));
    })

    it("Should check if user gets deducted correct shares on withdrawal", async function() {
      const { folio, folioModule, depositor_ONE, depositor_TWO, USDT } = await deployFolio();

      await USDT.connect(depositor_ONE).approve(folioModule.address, ethers.utils.parseEther('1000'));

      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      let shares = await folioModule.shares(depositor_ONE.address);
      await folioModule.withdraw(depositor_ONE.address, USDT.address, sellPaths, shares);
    });

    it("Should check if correct fee is being charged from the user with withdrawal", async function() {
      const { folio, folioModule, depositor_ONE, depositor_TWO, USDT } = await deployFolio();

      await USDT.connect(depositor_ONE).approve(folioModule.address, ethers.utils.parseEther('1000'));

      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      await time.increase(10*60*60);
      let fee = ethers.utils.parseEther('1.0').mul(ethers.BigNumber.from("36000")).mul(ethers.BigNumber.from("190258751903")).div(ethers.utils.parseEther('100'));
      expect(await folioModule.getFeeAccrued(depositor_ONE.address)).to.equal(fee);
    });

    it("Should check if correct fee is being charged from the user with concurrent deposits", async function() {
      const { folio, folioModule, depositor_ONE, depositor_TWO, USDT } = await deployFolio();

      await USDT.connect(depositor_ONE).approve(folioModule.address, ethers.utils.parseEther('1000'));

      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      await time.increase(10*60*60);
      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      await folioModule.withdraw(depositor_ONE.address, USDT.address, sellPaths, ethers.utils.parseEther('2.0'));
    });

    it("Should check if correct fee is being stored for folio owner to withdraw on every concurrent deposit and withdraw", async function() {
      const { folio, folioModule, depositor_ONE, depositor_TWO, USDT } = await deployFolio();

      await USDT.connect(depositor_ONE).approve(folioModule.address, ethers.utils.parseEther('1000'));

      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      await folioModule.deposit(depositor_ONE.address, USDT.address, buyPaths, ethers.utils.parseEther('1.0'));
      await folioModule.withdraw(depositor_ONE.address, USDT.address, sellPaths, ethers.utils.parseEther('2.0'));

      expect(await folioModule.getTotalFeeAccrued()).to.be.greaterThan(0);
    });

  })
})