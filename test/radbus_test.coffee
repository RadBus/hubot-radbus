chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'
nock = require 'nock'
moment = require 'moment-timezone'
RobotStub = require './RobotStub'
expect = chai.expect

describe "radbus package", ->
  beforeEach ->
    process.env.HUBOT_RADBUS_API_BASE_URL = 'http://radbus-base-url.com'
    process.env.HUBOT_RADBUS_API_KEY = 'radbus-api-key'
    process.env.HUBOT_RADBUS_TIMEZONE = 'America/Chicago'

    # disable all non-mocked network traffic
    nock.disableNetConnect()
    # except what we mock
    nock('http://radbus-base-url.com')
      .get('/oauth2')
      .reply(200, {
        client_id: 'client-id'
        client_secret: 'client-secret'
      })

    @msg =
      send: sinon.spy()
      message:
        user:
          name: 'Foo_User'
      # use actual HTTP client
      http: (url) -> require('scoped-http-client').create url

    @userData =
      foo_user: {}
      bar_user: {}

    @robot = new RobotStub @msg, @userData

    require('../src/radbus')(@robot)

  describe "when overheard 'bus or drive', Hubot", ->

    it "should reply with a witty response", ->
      msg = @msg
      @robot.doHear('bus or drive').then ->
        expect(msg.send).to.not.have.been.calledWithMatch /\n/

  describe "when someone gives it their RadBus refresh token, Hubot", ->
    beforeEach ->
      @userData.foo_user.authValue = 'Bearer old-value'
      @robot.doRespond 'bus token foo-refresh-token'

    it "should set the user's refresh token", ->
      expect(@userData.foo_user).to.have.property 'refreshToken', 'foo-refresh-token'

    it "should clear the user's auth value", ->
      expect(@userData.foo_user).to.not.have.property 'authValue'

    it "should respond with a 'thank you' message", ->
      expect(@msg.send).to.have.been.calledWithMatch /thanks @foo_user/i

  describe "when asked for bus times", ->

    mockDepartureRequest = (accessToken) ->
      nock('http://radbus-base-url.com', reqheaders:
          'Accept': 'application/json'
          'API-Key': 'radbus-api-key'
          'Authorization': "Bearer #{accessToken}"
        )
        .get('/departures')

    describe "by the current user, Hubot", ->
      beforeEach ->
        @userData.foo_user.refreshToken = 'foo-refresh-token'
        @userData.foo_user.authValue = 'Bearer foo-access-token'

      mockNewAccessTokenCall = ->
        nock('https://accounts.google.com', reqheaders:
            'Accept': 'application/json'
            'Content-Type': 'application/x-www-form-urlencoded'
          )
          .post('/o/oauth2/token',
            client_id: 'client-id'
            client_secret: 'client-secret'
            refresh_token: 'foo-refresh-token'
            grant_type: 'refresh_token'
          )
          .reply(200, {
            token_type: 'Bearer'
            access_token: 'new-access-token'
            expires_in: 1000
          })

      it "should respond with an apology and instructions if the user hasn't already provided a refresh token", ->
        delete @userData.foo_user.refreshToken
        msg = @msg

        @robot.doRespond('bus me').then ->
          expect(msg.send).to.have.been.calledWithMatch /sorry foo_user/i

      it "should respond with a first message that is looking up departures", ->
        msg = @msg

        scope = mockDepartureRequest('foo-access-token')
          .reply(200, [])

        @robot.doRespond('bus me').then ->
          expect(msg.send).to.have.been.calledWithMatch /@foo_user, give me a moment to look up those bus depatures/i

          scope.done()

      it "should obtain an auth token if one doesn't exist for the user", ->
        delete @userData.foo_user.authValue
        userData = @userData

        scopes = [
          mockNewAccessTokenCall(),
          mockDepartureRequest('new-access-token')
            .reply(200, [])
        ]

        @robot.doRespond('bus me').then ->
          expect(userData.foo_user).to.have.property 'authValue', 'Bearer new-access-token'

          scope.done() for scope in scopes

      it "should obtain a fresh access token if the existing one had expired while fetching departures", ->
        userData = @userData

        scopes = [
          # existing access token has expired on first call to get departures
          mockDepartureRequest('foo-access-token')
            .reply(401),

          # call to get new access token
          mockNewAccessTokenCall(),

          # departure call with new access token will work
          mockDepartureRequest('new-access-token')
            .reply(200, [])
        ]

        @robot.doRespond('bus me').then ->
          expect(userData.foo_user).to.have.property 'authValue', 'Bearer new-access-token'

          scope.done() for scope in scopes

      it "should respond with the expected message if there is no departure data", ->
        msg = @msg

        scope = mockDepartureRequest('foo-access-token')
          .reply(200, [])

        @robot.doRespond('bus me').then ->
          expect(msg.send).to.have.been.calledWithMatch /looks like you've got no upcoming departures/i

          scope.done()

      departures = (now) ->
        [
          {
            time: moment(now).add(15, 'minutes').add(5, 'seconds').format()
            route:
              id: '42'
              terminal: 'B'
            stop:
              description: '1st Ave and Main St'
          },
          {
            time: moment(now).add(30, 'minutes').add(5, 'seconds').format()
            route:
              id: '43'
            stop:
              description: '2nd Ave and Main St'
          }
        ]

      it "should respond with the expected message if is was departure data", ->
        now = moment()
        msg = @msg

        scope = mockDepartureRequest('foo-access-token')
          .reply(200, departures(now))

        @robot.doRespond('bus me').then ->
          expect(msg.send).to.have.been.calledWithMatch /here are your next bus times/i
          expect(msg.send).to.have.been.calledWithMatch /\d{1,2}\:\d{1,2} [AP]M \(15 minutes\)\: 42-B @ 1st Ave and Main St/i
          expect(msg.send).to.have.been.calledWithMatch /\d{1,2}\:\d{1,2} [AP]M \(30 minutes\)\: 43 @ 2nd Ave and Main St/i

          scope.done()

      it "should create shortened URL's if a depature has a geo location", ->
        now = moment()
        msg = @msg

        departures = departures(now)
        departures[0].location =
          lat: 44.9713808
          long: -93.2730451

        scopes = [
          mockDepartureRequest('foo-access-token')
            .reply(200, departures),

          nock('https://www.googleapis.com', reqheaders:
              'Accept': 'application/json'
              'Content-Type': 'application/json'
            )
            .post('/urlshortener/v1/url',
              longUrl: "http://www.google.com/maps/place/44.9713808,-93.2730451"
            )
            .reply(200, {
              id: 'http://goo.gl/foo-bar'
            })
        ]

        @robot.doRespond('bus me').then ->
          expect(msg.send).to.have.been.calledWithMatch /http:\/\/goo.gl\/foo-bar/i

          scope.done() for scope in scopes

    describe "for someone else, Hubot", ->
      beforeEach ->
        @userData.bar_user.refreshToken = 'bar-refresh-token'
        @userData.bar_user.authValue = 'Bearer bar-access-token'

      it "should fetch that user's bus times", ->
        msg = @msg

        scope = mockDepartureRequest('bar-access-token')
          .reply(200, [])

        @robot.doRespond('bus bar_user').then ->
          expect(msg.send).to.have.been.calledWithMatch /@bar_user, give me a moment to look up those bus depatures/i

          scope.done()
