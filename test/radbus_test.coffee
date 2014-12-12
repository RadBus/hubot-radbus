chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

expect = chai.expect

describe 'hello-world', ->
  beforeEach ->
    @robot =
      respond: sinon.spy()
      hear: sinon.spy()
    @msg =
      send: sinon.spy()

    require('../src/radbus')(@robot)

  describe 'bus or drive', ->

    it 'should register a hear listener, overhearing someone asking about busing or driving', ->
      expect(@robot.hear).to.have.been.calledWith /bus or drive/i

    it 'should reply with a single line of text', ->
      cb = @robot.hear.firstCall.args[1]
      cb @msg
      expect(@msg.send).to.not.have.been.calledWithMatch /\n/

  describe 'bus token', ->

    # TODO: finish

  describe 'bus me', ->

    # TODO: finish

  describe 'bus @user', ->

    # TODO: finish
