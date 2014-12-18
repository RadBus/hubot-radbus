Q = require 'q'

module.exports = class RobotStub
  constructor: (@msg, userData) ->
    @responds = []
    @hears = []

    userData = userData ?= {}
    brainData =
      radbus: userData

    @brain =
      get: (key) -> brainData[key]
      set: (key, value) -> brainData[key] = value
      save: () ->

  respond: (regex, cb) ->
    @responds.push
      regex: regex
      cb: cb

  hear: (regex, cb) ->
    @hears.push
      regex: regex
      cb: cb

  _do: (text, handlers) ->
    promises =
      for h in handlers
        m = text.match h.regex
        if m
          @msg.match = m
          Q.resolve h.cb(@msg)
        else
          Q.resolve()
    Q.all promises

  doRespond: (text) -> @_do text, @responds

  doHear: (text) -> @_do text, @hears
