local capabilities = require "st.capabilities"
local Zwave = require "st.zwave"
local zw = require "st.zwave.commands"
local log = require "log"

local YALE_MANUFACTURER_ID = 0x4003
local YALE_LOCK_MODEL_ID = 0x0800
local YALE_LOCK_FINGERPRINT = string.format("%04X-%04X-003B", YALE_MANUFACTURER_ID, YALE_LOCK_MODEL_ID)

local function device_added(driver, device)
    log.info("device_added: " .. device:get_name())
    device:send(Zwave.zwave.Command.BATTERY_GET())
    device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
  end

local function setAutoRelock(device, autoRelock, autoRelockTime)
  if autoRelock then
    device:send(Zwave.zwave.Command.CONFIGURATION_SET({
      configuration_value = autoRelockTime,
      parameter_number = 3,
      size = 1,
      scaled_configuration_value = autoRelockTime,
      precision = 0
    }))
  end
end

local function lock(device)
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_SET({
    operation_type = 0x01
  }))
end

local function unlock(device)
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_SET({
    operation_type = 0x02
  }))
end

local function refresh(device)
  device:send(Zwave.zwave.Command.BATTERY_GET())
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end

local function configure(device, configuration)
  local autoRelock = configuration.auto_relock or false
  local autoRelockTime = configuration.auto_relock_time or 30
  local statusReport = configuration.status_report or false
  local audibleAlarm = configuration.audible_alarm or false

  if statusReport then
    device:enable_debugging()
  else
    device:disable_debugging()
  end

  if audibleAlarm then
    device:send(Zwave.zwave.Command.CONFIGURATION_SET({
      configuration_value = 255,
      parameter_number = 5,
      size = 1,
      scaled_configuration_value = 255,
      precision = 0
    }))
  else
    device:send(Zwave.zwave.Command.CONFIGURATION_SET({
      configuration_value = 0,
      parameter_number = 5,
      size = 1,
      scaled_configuration_value = 0,
      precision = 0
    }))
  end

  setAutoRelock(device, autoRelock, autoRelockTime)
end

local function handleLockCommand(driver, device, command)
  log.debug("handleLockCommand: " .. command.name)
  lock(device)
end

local function handleUnlockCommand(driver, device, command)
  log.debug("handleUnlockCommand: " .. command.name)
  unlock(device)
end

local function handleConfigureCommand(driver, device, command)
  log.debug("handleConfigureCommand: " .. command.name)
  configure(device, command.args.configuration)
end

local function handleRefreshCommand(driver, device, command)
  log.debug("handleRefreshCommand: " .. command.name)
  refresh(device)
end

local function device_preferences()
    return {
      {
        type = "paragraph",
        label = "Enter the Yale Lock settings below.",
      },
      {
        type = "input",
        name = "autoLockTime",
        label = "Auto-lock Time (seconds)",
        description = "Enter the time (in seconds) after which the lock will automatically lock itself. Enter 0 to disable auto-lock.",
        default = "30",
        required = true,
        pattern = "%d+",
      },
      {
        type = "input",
        name = "lockSoundVolume",
        label = "Lock Sound Volume (0-10)",
        description = "Enter a value from 0 to 10 to adjust the lock sound volume. Enter 0 to disable the lock sound.",
        default = "5",
        required = true,
        pattern = "%d+",
      },
      {
        type = "input",
        name = "beeperVolume",
        label = "Beeper Volume (0-10)",
        description = "Enter a value from 0 to 10 to adjust the beeper volume. Enter 0 to disable the beeper.",
        default = "5",
        required = true,
        pattern = "%d+",
      },
      {
        type = "input",
        name = "wrongCodeLimit",
        label = "Wrong Code Limit (1-10)",
        description = "Enter the number of times an incorrect code can be entered before the lock disables itself for a set amount of time. Enter 0 to disable this feature.",
        default = "5",
        required = true,
        pattern = "%d+",
      },
      {
        type = "input",
        name = "wrongCodeDisableTime",
        label = "Wrong Code Disable Time (minutes)",
        description = "Enter the time (in minutes) the lock will disable itself after the wrong code limit has been reached. Enter 0 to disable this feature.",
        default = "5",
        required = true,
        pattern = "%d+",
      },
    }
  end

local function device_init(driver, device)
  log.info("device_init: " .. device:get_name())
  device:send(Zwave.zwave.Command.BATTERY_GET())
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end

local function device_event_handler(driver, device, event)
    if event.type == zwave.command_classes.USER_CODE.ID then
      if event.command == zwave.command_classes.USER_CODE.USER_CODE_REPORT.ID then
        device:emit_event( capabilities.lockCodes.lockCode(), {
          value = true,
          data = { codeId = event.args.user_id }
        })
      end
    elseif event.type == zwave.command_classes.NOTIFICATION.ID then
      if event.command == zwave.command_classes.NOTIFICATION.NOTIFICATION_REPORT.ID then
        local notif_type = event.args.notification_type
        if notif_type == zwave.command_classes.NOTIFICATION.notification_type.ACCESS_CONTROL.ID then
          if event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.MANUAL_LOCK.ID then
            device:emit_event(capabilities.lock.lock(), { value = "locked" })
          elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.MANUAL_UNLOCK.ID then
            device:emit_event(capabilities.lock.lock(), { value = "unlocked" })
          elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.AUTO_LOCK.ID then
            device:emit_event(capabilities.lock.lock(), { value = "locked" })
          elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.AUTO_UNLOCK.ID then
            device:emit_event(capabilities.lock.lock(), { value = "unlocked" })
          end
        end
      end
    end
  end

  local function configure(device)
    -- Set the device parameters based on the user preferences
    for _, preference in ipairs(preferences) do
      local value = device.preferences[preference.key]
      if value ~= nil then
        local cmd = preference.zwave_set(value)
        device:send(cmd)
      end
    end
  
    -- Configure the auto re-lock time if specified
    local autoReLockTime = device.preferences.autoReLockTime
    if autoReLockTime ~= nil then
      local autoReLockTimeCmd = zwave.Command.CONFIGURE({
        parameter_number = 8,
        size = 1,
        configuration_value = autoReLockTime
      })
      device:send(autoReLockTimeCmd)
    end
  end

  local function updatedevice(device, event)
    local event_type = event.type
    if event_type == zwave.CommandClass.NOTIFICATION then
      local alarm_type = event.args.notification_type
      if alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_KEYPAD or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_COMMAND or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_RF or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_AUTO
      then
        device:emit_event(locks.locked())
      elseif alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_KEYPAD or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_COMMAND or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_RF
      then
        device:emit_event(locks.unlocked())
      end
    elseif event_type == zwave.CommandClass.BATTERY then
      local battery_level = event.args.battery_level
      device:emit_event(battery.battery(battery_level))
    end
  end
  
  local function capabilities()
    return {
      locks = {
        supported = true,
        command = {
          lock = zwave.CommandClass.DOOR_LOCK.LOCK(),
          unlock = zwave.CommandClass.DOOR_LOCK.UNLOCK(),
          lockJammed = zwave.CommandClass.DOOR_LOCK.LOCK_JAMMED(),
          unlockJammed = zwave.CommandClass.DOOR_LOCK.UNLOCK_JAMMED(),
          lockUnknown = zwave.CommandClass.DOOR_LOCK.LOCK_UNKNOWN(),
          unlockUnknown = zwave.CommandClass.DOOR_LOCK.UNLOCK_UNKNOWN()
        },
        status = {
          lock = locks.locked(),
          unlock = locks.unlocked(),
          lockJammed = locks.lockJammed(),
          unlockJammed = locks.unlockJammed(),
          lockUnknown = locks.lockUnknown(),
          unlockUnknown = locks.unlockUnknown()
        }
      },
      refresh = {
        supported = true,
        command = refresh.refresh()
      },
      battery = battery.battery()
    }
  end


  
