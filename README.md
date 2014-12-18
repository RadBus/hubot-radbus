# hubot-radbus

**RadBus API integration for Hubot**

[![Build Status](https://travis-ci.org/twistedstream/hubot-radbus.svg?branch=master)](https://travis-ci.org/twistedstream/hubot-radbus)

Reports to the current user what their upcoming bus times are using the RadBus API.  If it's AM, they get times for their buses heading into the office.  Likewise, if it's PM, they get times for buses that will take them home.

**NOTE:** RadBus currently only works in the Twin Cities (Minneapolis/St. Paul, MN) area.

## Installation

[![NPM](https://nodei.co/npm/hubot-radbus.png?downloads=true)](https://nodei.co/npm/hubot-radbus/)

In your Hubot repository, run:

`npm install hubot-radbus --save`

Then add **hubot-radbus** to your `external-scripts.json`:

```json
["hubot-radbus"]
```

## Configuration

`RadBus` requires a bit of configuration to get everything working:

* **HUBOT_RADBUS_TIMEZONE** - Set to `America/Chicago` since RadBus only supports the Twin Cities metro area, which is in the Chicago timezone
* **HUBOT_RADBUS_API_BASE_URL** - Set to `https://api.radbus.io/v1`
* **HUBOT_RADBUS_API_KEY** - Set to the an API key that has been registered to your instance of Hubot.  Go [here](https://github.com/RadBus/api/wiki/Client-Authentication#obtaining-your-api-key) for more information on how to request an API key.

## Commands

```
hubot bus token {token} - Sets your application token (refresh token) so Hubot can call the RadBus API from the server-side on your behalf.
hubot bus me [route] - Returns your upcoming bus schedule (to work if its AM, to home if PM).  Optionally you can specify a route and it will only reply with departures from that route.
hubot bus {user} [route] - Same as 'bus me' but for a different Hubot user.
```

- Before `bus me` will return anything useful, it needs to know your bus schedule.  The easiest way to do that is to go build your personalized schedule using a RadBus app (for example: https://www.radbus.io).
- Before Hubot will be allowed to make API calls on behalf of your user you need to aquire an application token (otherwise known as a 'refresh token') and register it with Hubot (see `bus token` command above).  If you don't have a registered application token, Hubot will tell you what you need to do to get one.

## Example Interactions

```
busrider> hubot bus me
hubot> Hey @busrider, give me a moment to look up those bus depatures...
       @busrider, here are your next bus times:
       7:23 AM (1 minuteundefined): 264-C @ I-35W and County Rd C Park & Ride
         http://goo.gl/WHgnd7
       7:39 AM (17 minutes): 264-C @ I-35W and County Rd C Park & Ride
         http://goo.gl/WbGdCc
       7:57 AM (35 minutes): 264-C @ I-35W and County Rd C Park & Ride
```

## Resources

* http://dev.radbus.io
