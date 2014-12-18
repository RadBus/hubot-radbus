# Description:
#   Allows Hubot to call the RadBus API.
#
# Commands:
#   hubot bus token {token} - sets your application token so Hubot can call the RadBus API
#   hubot bus me - returns your upcoming bus schedule (to work if its AM, to home if PM)
#
# Author:
#   twistedstream

Q = require 'q'
QS = require 'querystring'
util = require 'util'
moment = require 'moment-timezone'

LOG_PREFIX = 'BUS'

handleResponse = (err, res, body, d) ->
  if err
    d.reject err
  else
    if res.statusCode is 200
      d.resolve(JSON.parse body)
    else
      d.reject {
        statusCode: res.statusCode
        body: body
      }


callRadBus = (msg, endpoint, authValue) ->
  url = "#{process.env.HUBOT_RADBUS_API_BASE_URL}#{endpoint}"

  headers =
    Accept: 'application/json'
    'API-Key': process.env.HUBOT_RADBUS_API_KEY
  if authValue then headers['Authorization'] = authValue

  d = Q.defer()

  msg.http(url)
    .headers(headers)
    .get() (err, res, body) ->
      handleResponse err, res, body, d

  d.promise

getAuthToken = (msg, oAuth2Info, refreshToken) ->
  url = 'https://accounts.google.com/o/oauth2/token'

  headers =
    Accept: 'application/json'
    'Content-Type': 'application/x-www-form-urlencoded'

  data = QS.stringify(
    client_id: oAuth2Info.client_id,
    client_secret: oAuth2Info.client_secret,
    refresh_token: refreshToken,
    grant_type: 'refresh_token'
  )

  d = Q.defer()

  msg.http(url)
    .headers(headers)
    .post(data) (err, res, body) ->
      handleResponse err, res, body, d

  d.promise

shortenUrl = (msg, longUrl) ->
  url = 'https://www.googleapis.com/urlshortener/v1/url'

  headers =
    Accept: 'application/json'
    'Content-Type': 'application/json'

  data = JSON.stringify longUrl: longUrl

  d = Q.defer()

  msg.http(url)
    .headers(headers)
    .post(data) (err, res, body) ->
      handleResponse err, res, body, d

  d.promise.then (json) ->
    json.id

getRadBusUserData = (robot, userName) ->
  radbus = robot.brain.get 'radbus'

  console.log "radbus = #{util.inspect(radbus, depth: null)}"

  if !radbus
    radbus = {}
    robot.brain.set 'radbus', radbus
    robot.brain.save()

  userData = radbus[userName]
  if !userData
    userData = {}
    radbus[userName] = userData
    robot.brain.save()

  userData

ensureAuthToken = (robot, msg, userData, logPrefix) ->
  if userData.authValue
    Q.resolve()
  else
    console.log "#{logPrefix} Calling RadBus API to get the RadBus API's Google API client ID & secret..."
    callRadBus(msg, '/oauth2').then (oAuth2Info) ->
      console.log "#{logPrefix} Done. oAuth2Info.client_id = #{oAuth2Info.client_id}"

      console.log "#{logPrefix} Getting new auth token from user's refresh token..."
      getAuthToken(msg, oAuth2Info, userData.refreshToken).then (authTokenInfo) ->
        console.log "#{logPrefix} Done. Refresh token expires in #{authTokenInfo.expires_in} seconds."

        userData.authValue = "#{authTokenInfo.token_type} #{authTokenInfo.access_token}"
        robot.brain.save()

        Q.resolve()

getDepartures = (robot, msg, userData, logPrefix) ->
  callDepartures = () -> callRadBus msg, '/departures', userData.authValue

  callDepartures()
    # get new auth token if the current one has expired, then attempt to get departures again
    .fail (err) ->
      if err.statusCode is 401
        console.log "#{logPrefix} User's auth token has expired.  Obtaining a fresh one..."

        delete userData.authValue
        ensureAuthToken(robot, msg, userData, logPrefix).then ->
          callDepartures()

      else
        throw err

module.exports = (robot) ->
  robot.hear /bus or drive/i, (msg) ->
    msg.send "Pro tip: always take the bus"

  robot.respond /bus @?(\S+)( (\S+))?/i, (msg) ->
    # detect command/user name
    command = msg.match[1].toLowerCase();
    arg = msg.match[3]
    if arg then arg = arg.toLowerCase()

    if command is 'token'
      # set token command

      userName = msg.message.user.name.toLowerCase()
      refreshToken = msg.match[3]

      userData = getRadBusUserData robot, userName
      userData.refreshToken = refreshToken
      delete userData.authValue

      msg.send "Thanks @#{userName} for the RadBus API token!  You can now check your bus times using 'bus me'.\n" +
               "If you need to set or change your schedule, visit: https://www.radbus.io"

    else if not (command is 'or' and arg is 'drive')
      userName = command
      if userName is 'me'
        userName = msg.message.user.name.toLowerCase()

      logPrefix = "#{LOG_PREFIX}(@#{userName}):"

      userData = getRadBusUserData robot, userName
      if !userData.refreshToken
        msg.send "Sorry #{userName}, I can't get at your bus schedule until you give me your RadBus API application token.\n" +
                 "Do this:\n" +
                 "1. Go to https://www.radbus.io/app-token.html to obtain a token.\n" +
                 "2. Use the 'bus token {your-token}' to tell me what your token is."

      else
        msg.send "Hey @#{userName}, give me a moment to look up those bus depatures..."

        chain = ensureAuthToken(robot, msg, userData, logPrefix).then ->
          console.log "#{logPrefix} Getting user's departures..."

          getDepartures(robot, msg, userData, logPrefix).then (departures) ->
            console.log "#{logPrefix} Done. API returned #{departures.length} departures."

            #if user specified a route/terminal filter, filter out departures that don't match
            if arg
              match = /^(\d+)(\w)?$/.exec arg
              routeFilter = match[1]
              terminalFilter = match[2]
              if terminalFilter then terminalFilter = terminalFilter.toUpperCase()

              console.log "#{logPrefix} Filtering depatures by route #{routeFilter}" + if terminalFilter then " and terminal #{terminalFilter}" else ""

              departures = departures.filter (departure) ->
                departure.route.id is routeFilter and (!terminalFilter or departure.route.terminal is terminalFilter)

            if (departures.length is 0)
              msg.send "@#{userName}, looks like you've got no upcoming departures."
            else
              formattedDeparturePromises = departures.map (departure) ->
                departureTime = moment(departure.time).tz process.env.HUBOT_RADBUS_TIMEZONE
                wait = departureTime.diff moment(), 'minutes'

                formattedDeparture =
                  time: departureTime.format 'LT'
                  wait: wait + " minute" + (if wait is 1 then "" else "s")
                  route: departure.route.id + (if departure.route.terminal then "-#{departure.route.terminal}" else '')
                  departure: departure.stop.description
                  locationLink: ''

                if departure.location
                  longUrl = "http://www.google.com/maps/place/#{departure.location.lat},#{departure.location.long}"

                  shortenUrl(msg, longUrl).then (shortUrl) ->
                    formattedDeparture.locationLink = "\n #{shortUrl}"

                    Q formattedDeparture
                else
                  Q formattedDeparture

              Q.all(formattedDeparturePromises).then (formattedDepartures) ->
                message = "@#{userName}, here are your next bus times:\n" +
                  formattedDepartures.map((dep) ->
                    "#{dep.time} (#{dep.wait}): #{dep.route} @ #{dep.departure}#{dep.locationLink}"
                  ).join('\n')

                msg.send message

        chain.fail (err) ->
          console.error "#{logPrefix} Something got borked: #{err.stack || util.inspect(err, depth: null)}"
          Q.reject err
