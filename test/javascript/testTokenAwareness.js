const MultiSigWallet = artifacts.require('MultiSigWallet')
const TestToken = artifacts.require('TestToken')

const web3 = MultiSigWallet.web3
const deployMultisig = (tokenAddress, owners, confirmations) => {
    return MultiSigWallet.new(tokenAddress, owners, confirmations)
}

const deployToken = () => {
    return TestToken.new()
}

const utils = require('./utils')
const deposit = 1000

contract('MultiSigWallet', (accounts) => {
    let multisigInstance
    const requiredConfirmations = 2

    beforeEach(async () => {
        tokenInstance = await deployToken()
        assert.ok(tokenInstance)
        multisigInstance = await deployMultisig(tokenInstance.address, [accounts[0], accounts[1], accounts[2]], requiredConfirmations)
        assert.ok(multisigInstance)
        assert.equal(await multisigInstance.getTokenContract(), tokenInstance.address)
    })


    it('multisig do not receive ETC', async () => {
        var test = function() {
          web3.eth.sendTransaction({to: multisigInstance.address, value: deposit, from: accounts[0]})
        }

        assert.throws(test, 'VM Exception while processing transaction: invalid opcode');
        const balance = await utils.balanceOf(web3, multisigInstance.address)
        assert.equal(balance.valueOf(), 0)
        
    })

    it('multisig can not prepare call for random contract', async () => {
        tokenInstance2 = await deployToken()
        const transferAnotherToken = tokenInstance2.contract.transfer.getData(accounts[3], deposit)

        try {
            await multisigInstance.submitTransaction(tokenInstance2.address, 0, transferAnotherToken, {from: accounts[0]})
        } catch (e) {
            // Need better test design for this case but wrapper just awfully fails
        }
        assert.equal(await multisigInstance.getTransactionCount(true, true), 0)
    })

    it('multisig can prepare tokens transfer', async () => {
        const transferToken = tokenInstance.contract.transfer.getData(accounts[3], deposit)
        await multisigInstance.submitTransaction(tokenInstance.address, 0, transferToken, {from: accounts[0]}),
        assert.equal(await multisigInstance.getTransactionCount(true, true), 1)
    })
})