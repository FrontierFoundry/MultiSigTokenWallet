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

contract('MultiSigWallet', (accounts) => {
    let multisigInstance
    const requiredConfirmations = 2

    const excludePending = false
    const includePending = true
    const excludeExecuted = false
    const includeExecuted = true


    beforeEach(async () => {
        tokenInstance = await deployToken()
        assert.ok(tokenInstance)
        multisigInstance = await deployMultisig(tokenInstance.address, [accounts[0], accounts[1], accounts[2]], requiredConfirmations)
        assert.ok(multisigInstance)
        assert.equal(await multisigInstance.getTokenContract(), tokenInstance.address)
    })

    it('execution from a non-owner address fails', async () => {
        const addOwnerData = multisigInstance.contract.addOwner.getData(accounts[3])
        const proposedTransactionId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 888, addOwnerData, {from: accounts[1]}),
            'transactionId', null, 'Submission')

        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, includePending, excludeExecuted),
            [proposedTransactionId]
        )

        utils.assertThrowsAsynchronously(
            () => multisigInstance.executeTransaction(proposedTransactionId, {from: accounts[9]})
        )
    })

    it('execution fails if the sender is a wallet owner but didnt confirm the transaction first', async () => {
        const addOwnerData = multisigInstance.contract.addOwner.getData(accounts[3])
        const proposedTransactionId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, addOwnerData, {from: accounts[1]}),
            'transactionId', null, 'Submission')

        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, includePending, excludeExecuted),
            [proposedTransactionId]
        )

        utils.assertThrowsAsynchronously(
            () => multisigInstance.executeTransaction(proposedTransactionId, {from: accounts[0]})
        )
    })

    it('execution from a right sender works', async () => {
        const addOwnerData = multisigInstance.contract.addOwner.getData(accounts[3])
        const proposedTransactionId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, addOwnerData, {from: accounts[1]}),
            'transactionId', null, 'Submission')

        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, includePending, excludeExecuted),
            [proposedTransactionId]
        )

        await multisigInstance.executeTransaction(proposedTransactionId, {from: accounts[1]})
        assert.ok((await multisigInstance.transactions(proposedTransactionId))[0])
    })

    it('execution fails if tx does not exist', async () => {
        // Try to execute a transaction tha does not exist fails
        const unknownTransactionId = 999
        utils.assertThrowsAsynchronously(
            () => multisigInstance.executeTransaction(unknownTransactionId, {from: accounts[0]})
        )
    })
})