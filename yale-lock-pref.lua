-- Import required modules and define device capabilities
local capabilities = require "st.capabilities"
local Zwave = require "st.zwave"
local zw = require "st.zwave.commands"
local log = require "log"
local Battery = capabilities.battery
local Lock = capabilities.lock
local Refresh = capabilities.refresh

-- Define constants
local YALE_MANUFACTURER_ID = 0x4003
local YALE_LOCK_MODEL_ID = 0x0800
local YALE_LOCK_FINGERPRINT = string.format("%04X-%04X-003B", YALE_MANUFACTURER_ID, YALE_LOCK_MODEL_ID)


-- .
-- . device_init (ialization)
-- .
-- .
-- This local function is called by the driver to initialize the device when it is first added to the network
local function device_init(driver, device)
  -- Log a message indicating that the device has been initialized
  log.info("device_init: " .. device:get_name())
  
  -- Send a command to the device to get its current battery level
  device:send(Zwave.zwave.Command.BATTERY_GET())
  
  -- Send a command to the device to get its current door lock operation state
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end


-- .
-- . device_added
-- .
-- .
-- This function is called when a new device is added to the hub
local function device_added(driver, device)
  -- Log the name of the added device
  log.info("device_added: " .. device:get_name())
  -- Send a battery get command to the device to retrieve its current battery level
  device:send(Zwave.zwave.Command.BATTERY_GET())
  -- Send a door lock operation get command to the device to retrieve its current lock status
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end



-- .
-- . device_removed
-- .
-- .
-- This function is called when a device is removed from the hub
local function device_removed(driver, device)
  -- Check if the removed device is a lock
  if device.preferences.deviceType == "lock" then
    -- Reset the lock status to unknown
    device:emit_event(capabilities.lock.lock(), {value = "unknown"})
    -- Remove all lock codes associated with the lock
    device:emit_event(capabilities.lockCodes.lockCodes(), {value = {}})
    -- Set the lock jammed status to false
    device:emit_event(capabilities.lock.lockJammed(), {value = false})
  end
end


-- .
-- . device_event_handler
-- .
-- .
-- This function handles events for the lock device
-- @param driver: the driver instance
-- @param device: the device instance that triggered the event
-- @param event: the event that was triggered
-- Define device capabilities
local function device_event_handler(driver, device, event)
  -- Check if the event is related to user codes
  if event.type == zwave.command_classes.USER_CODE.ID then
    if event.command == zwave.command_classes.USER_CODE.USER_CODE_REPORT.ID then
      -- Emit an event when a user code is reported
      device:emit_event( capabilities.lockCodes.lockCode(), {
        value = true,
        data = { codeId = event.args.user_id }
      })
    end
  -- Check if the event is related to notifications
  elseif event.type == zwave.command_classes.NOTIFICATION.ID then
    if event.command == zwave.command_classes.NOTIFICATION.NOTIFICATION_REPORT.ID then
      local notif_type = event.args.notification_type
      -- Check if the notification is related to access control
      if notif_type == zwave.command_classes.NOTIFICATION.notification_type.ACCESS_CONTROL.ID then
        -- Check if the lock was manually locked or unlocked
        if event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.MANUAL_LOCK.ID then
          device:emit_event(capabilities.lock.lock(), { value = "locked" })
        elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.MANUAL_UNLOCK.ID then
          device:emit_event(capabilities.lock.lock(), { value = "unlocked" })
        -- Check if the lock was automatically locked or unlocked
        elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.AUTO_LOCK.ID then
          device:emit_event(capabilities.lock.lock(), { value = "locked" })
        elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.AUTO_UNLOCK.ID then
          device:emit_event(capabilities.lock.lock(), { value = "unlocked" })
        -- Check if the lock is jammed
        elseif event.args.event == zwave.command_classes.NOTIFICATION.event.access_control.JAMMED.ID then
          device:emit_event(capabilities.lock.lock(), { value = "jammed" })
        end
      end
    end
  -- Check if the event is related to battery level
  elseif event.type == zwave.command_classes.BATTERY.ID then
    if event.command == zwave.command_classes.BATTERY.BATTERY_REPORT.ID then
      -- Emit an event when a battery report is received
      device:emit_event(capabilities.battery.battery(), { value = event.args.battery_level })
    end
  -- Check if the event is related to the door lock state
  elseif event.type == zwave.command_classes.DOOR_LOCK.ID then
    if event.command == zwave.command_classes.DOOR_LOCK.LOCK_REPORT.ID then
      -- Emit an event when a lock report is received
      if event.args.lock_state == zwave.command_classes.DOOR_LOCK.lock_state.LOCKED then
        device:emit_event(capabilities.lock.lock(), { value = "locked" })
      elseif event.args.lock_state == zwave.command_classes.DOOR_LOCK.lock_state.UNLOCKED then
        device:emit_event(capabilities.lock.lock(), { value = "unlocked" })
      end
    end
  end
end
      


-- .
-- . setAutoRelock
-- .
-- .
-- This function sets the auto relock time for the specified device, if autoRelock is true
-- and sends a configuration command to the device with the specified autoRelockTime.
-- If autoRelock is false, the function does nothing.
-- @param device The device to set the auto relock time for.
-- @param autoRelock A boolean value indicating whether auto relock should be enabled.
-- @param autoRelockTime The time interval in seconds for the auto relock to be set to.
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


-- .
-- . lock
-- .
-- .
-- Function: lock
-- Input: device (zwave device)
-- Output: none
-- Description: sends a door lock operation set command to the device with operation_type = 0x01, which locks the door
local function lock(device)
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_SET({
    operation_type = 0x01
  }))
end

-- .
-- . unlock
-- .
-- .
-- This function is called to unlock the door
local function unlock(device)
  -- Sends the DOOR_LOCK_OPERATION_SET command to the device with operation_type value of 0x02 to unlock the door
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_SET({
    operation_type = 0x02
  }))
end




-- .
-- . refresh
-- .
-- .
-- This function sends commands to the device to refresh its battery and door lock operation status
local function refresh(device)
  -- Send a command to get the device's battery status
  device:send(Zwave.zwave.Command.BATTERY_GET())
  
  -- Send a command to get the device's door lock operation status
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end




-- .
-- . configure
-- .
-- .
-- Configure device with given configuration
local function configure(device, configuration)
  -- Set autoRelock to false if not provided in the configuration
  local autoRelock = configuration.auto_relock or false
  -- Set autoRelockTime to 30 seconds if not provided in the configuration
  local autoRelockTime = configuration.auto_relock_time or 30
  -- Set statusReport to false if not provided in the configuration
  local statusReport = configuration.status_report or false
  -- Set audibleAlarm to false if not provided in the configuration
  local audibleAlarm = configuration.audible_alarm or false

  -- Enable debugging if statusReport is true, otherwise disable debugging
  if statusReport then
    device:enable_debugging()
  else
    device:disable_debugging()
  end

  -- Set the audible alarm configuration value based on the audibleAlarm value
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

  -- Set the autoRelock configuration value based on the autoRelock and autoRelockTime values
  setAutoRelock(device, autoRelock, autoRelockTime)
end







-- This function handles the lock command by locking the device and logging the command name
local function handleLockCommand(driver, device, command)
  log.debug("handleLockCommand: " .. command.name)
  lock(device)
end

-- This function handles the unlock command by unlocking the device and logging the command name
local function handleUnlockCommand(driver, device, command)
  log.debug("handleUnlockCommand: " .. command.name)
  unlock(device)
end

-- This function handles the configure command by configuring the device with the given arguments and logging the command name
local function handleConfigureCommand(driver, device, command)
  log.debug("handleConfigureCommand: " .. command.name)
  configure(device, command.args.configuration)
end

-- This function handles the refresh command by refreshing the device and logging the command name
local function handleRefreshCommand(driver, device, command)
  log.debug("handleRefreshCommand: " .. command.name)
  refresh(device)
end

-- This function returns a table with device preferences for the Yale Lock
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


  
