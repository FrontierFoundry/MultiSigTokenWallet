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
const ONE_DAY = 24*3600
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

        assert.throws(test, 'VM Exception while processing transaction: revert');
        const balance = await utils.balanceOf(web3, multisigInstance.address)
        assert.equal(balance.valueOf(), 0)
        
    })


    it('multisig can not prepare call for random contract', async () => {
        tokenInstance2 = await deployToken()
        const transferAnotherToken = tokenInstance2.contract.transfer.getData(accounts[3], deposit)

        try {
            await multisigInstance.submitTransaction(tokenInstance2.address, 0, transferAnotherToken, false, {from: accounts[0]})
        } catch (e) {
            // Need better test design for this case but wrapper just awfully fails
        }
        assert.equal(await multisigInstance.getTransactionCount(true, true), 0)
    })

    it('multisig can prepare tokens transfer', async () => {
        await multisigInstance.submitTransaction(accounts[1], deposit, "213123", true, {from: accounts[0]})
        assert.equal(await multisigInstance.getTransactionCount(true, true), 1)
    })

    it('multisig can not prepare zero token transfer', async () => {
        try {
            await multisigInstance.submitTransaction(accounts[1], 0, null, true ,{from: accounts[0]})
        } catch (e) {
            // Need better test design for this case but wrapper just awfully fails
        }
        assert.equal(await multisigInstance.getTransactionCount(true, true), 0)
    })

    it('test execution after requirements changed', async () => {
        const deposit = 1000        
        // Add owner wa_4
        const addOwnerData = multisigInstance.contract.addOwner.getData(accounts[3])
        const transactionId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, addOwnerData, false, {from: accounts[0]}),
            'transactionId',
            null,
            'Submission'
        )

        // There is one pending transaction
        const excludePending = false
        const includePending = true
        const excludeExecuted = false
        const includeExecuted = true
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, includePending, excludeExecuted),
            [transactionId]
        )

        // Update required to 1
        const newRequired = 1
        const updateRequirementData = multisigInstance.contract.changeRequirement.getData(newRequired)

        // Submit successfully
        const transactionId2 = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, updateRequirementData, false, {from: accounts[0]}),
            'transactionId',
            null,
            'Submission'
        )

        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 2, includePending, excludeExecuted),
            [transactionId, transactionId2]
        )

        // Confirm change requirement transaction
        await multisigInstance.confirmTransaction(transactionId2, {from: accounts[1]})
        assert.equal((await multisigInstance.required()).toNumber(), newRequired)
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, excludePending, includeExecuted),
            [transactionId2]
        )

        // Execution fails, because sender is not wallet owner
        utils.assertThrowsAsynchronously(
            () => multisigInstance.executeTransaction(transactionId, {from: accounts[9]})
        )

        // Because the # required confirmations changed to 1, the addOwner transaction can be executed now
        await multisigInstance.executeTransaction(transactionId, {from: accounts[0]})
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 2, excludePending, includeExecuted),
            [transactionId, transactionId2]
        )
    })
})