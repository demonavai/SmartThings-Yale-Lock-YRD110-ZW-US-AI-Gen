-- Yale Z-Wave Lock Driver for SmartThings
-- Model: YRD110-ZW-US
-- Author: ChatGPT & @demonavai
-- Date: 2023-03-26

local capabilities = require "st.capabilities"
local z_wave = require "st.zwave"
local device_management = require "st.device_management"
local utils = require "st.utils"
local log = require "log"


local YALE_ZWAVE_LOCK_FINGERPRINT = {
  mfr = "0129",
  prod = "0004",
  model = "0800"
}

local function is_yale_zwave_lock(device)
  return utils.device_fingerprint_match(device, YALE_ZWAVE_LOCK_FINGERPRINT)
end

-- .
-- . device_init (initialization)
-- .
-- .
-- This local function is called by the driver to initialize the device when it is first added to the network
local function device_init(driver, device)
  -- This function is called when the driver is first initialized

  -- Log a message indicating that the device has been initialized
  log.info("device_init: " .. device:get_name())
  
  -- Send a command to the device to get its current battery level
  device:send(Zwave.zwave.Command.BATTERY_GET())
  
  -- Send a command to the device to get its current door lock operation state
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())

  -- Retrieve the user codes from the device and store them in the user preferences
  for i = 1, 20 do
    local lockCode = device:getValue(zwave.command_classes.USER_CODE.ID, i)
    if lockCode ~= nil then
      local lockCodeLength = string.len(tostring(lockCode))
      if lockCodeLength >= 4 and lockCodeLength <= 6 then
        device.preferences["userCode" .. i] = string.format("%0" .. lockCodeLength .. "d", lockCode)
      else
        log.warn("Invalid lock code length for user " .. i .. ": " .. lockCodeLength)
      end
    end
  end
end

-- .
-- . device_added
-- .
-- .
-- This function is called when a new device is added to the hub
local function device_added(driver, device)
  -- This function is called when the device is added to SmartThings

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
  -- This function is called when the device is removed from SmartThings

  -- Check if the removed device is a lock
  -- ADDED SPACES IN FRONT OF "IF" BELOW INSTEAD OF PROPERLY INDENTING**************************************////////////
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
  -- This function handles events from the device

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
local function setAutoRelock(driver, device, value)
  -- Set the auto-relock feature based on the user's preference
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
local function lock(driver, device)
  -- Send the lock command to the device
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_SET({
    operation_type = 0x01
  }))
end

-- .
-- . unlock
-- .
-- .
-- This function is called to unlock the door
local function unlock(driver, device)
  -- Send the unlock command to the device

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
local function refresh(driver, device)
  -- Refresh the device's state

  -- Send a command to get the device's battery status
  device:send(Zwave.zwave.Command.BATTERY_GET())
  
  -- Send a command to get the device's door lock operation status
  device:send(Zwave.zwave.Command.DOOR_LOCK_OPERATION_GET())
end

-- .
-- . configure
-- .
-- .
-- Configure device with given configuration based on user preferences
local function configure(driver, device)
    -- Set autoRelock to false if not provided in the configuration
    local autoRelock = device.preferences.auto_relock or false
    -- Set autoRelockTime to 30 seconds if not provided in the configuration
    local autoRelockTime = device.preferences.auto_relock_time or 30
    -- Set statusReport to false if not provided in the configuration
    local statusReport = device.preferences.status_report or false
    -- Set audibleAlarm to false if not provided in the configuration
    local audibleAlarm = device.preferences.audible_alarm or false

    -- Enable debugging if statusReport is true, otherwise disable debugging
    if statusReport then
        device:enable_debugging()
    else
        device:disable_debugging()
    end

    -- Set the auto-relock feature based on the user preference
    if autoRelock then
        local cmd = zw.CONFIGURATION_SET({
        parameter_number = 111,
        size = 4,
        configuration_value = autoRelockTime,
        scaled_configuration_value = autoRelockTime,
        precision = 0
        })
        device:send(cmd)
    end

    -- Set the audible alarm configuration value based on the audibleAlarm value
    if audibleAlarm then
        local cmd = zw.CONFIGURATION_SET({
        configuration_value = 255,
        parameter_number = 5,
        size = 1,
        scaled_configuration_value = 255,
        precision = 0
        })
        device:send(cmd)
    else
        local cmd = zw.CONFIGURATION_SET({
        configuration_value = 0,
        parameter_number = 5,
        size = 1,
        scaled_configuration_value = 0,
        precision = 0
        })
        device:send(cmd)
    end
end
  

-- .
-- . handleLockCommand
-- .
-- .
-- This function handles the lock command by locking the device and logging the command name
local function handleLockCommand(driver, device, command)
    log.debug("handleLockCommand: " .. command.name)
    lock(device)
end

-- .
-- . handleUnlockCommand
-- .
-- .
-- This function handles the unlock command by unlocking the device and logging the command name.
local function handleUnlockCommand(driver, device, command)
    -- Send the unlock command to the device
    device:send(zw.send(zw.command_classes.DOOR_LOCK.ID, zw.command_classes.DOOR_LOCK.UNLOCK()))
    local result = command:success()
    if result == nil then
      log.warn("Unable to send unlock command")
    end
end
  
  

-- .
-- . handleConfigureCommand
-- .
-- .
-- This function handles the configure command by configuring the device with the given arguments and logging the command name
local function handleConfigureCommand(driver, device, command)
  -- Handle the configure command from the SmartThings app
  log.debug("handleConfigureCommand: " .. command.name)
  configure(device, command.args.configuration)
end

-- .
-- . handleRefreshCommand
-- .
-- .
-- This function handles the refresh command by refreshing the device and logging the command name
local function handleRefreshCommand(driver, device, command)
  -- Handle the refresh command from the SmartThings app
  log.debug("handleRefreshCommand: " .. command.name)
  refresh(device)
end

-- .
-- . device_preferences
-- .
-- .
-- This function returns a table with device preferences for the Yale Lock
local function device_preferences(driver, device)
    -- Retrieve the user preferences for the device from the SmartThings app
    -- ...
    local preferences = {}
  
    -- Add the main preferences to the 'preferences' table
    for _, main_preference in ipairs({
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
            type = "enum",
            name = "panelLockout",
            label = "Panel Lockout",
            description = "Enable or disable the panel lockout feature of the lock.",
            values = {
            { value = "enabled", label = "Enabled" },
            { value = "disabled", label = "Disabled" },
            },
            default = "disabled",
            required = true,
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
        -- ...
      }) do
        table.insert(preferences, main_preference)
      end

  -- Retrieve the existing user codes
    -- Create an empty table to store the user code preferences
    local userCodes = {}
    -- Loop through each of the 15 possible users
    for i = 1, 15 do
    -- Create a section header for each user
    table.insert(userCodes, {
        type = "section",
        label = "User " .. i .. " Settings",
        header = true,
    })
    -- Create a field for the user code
    table.insert(userCodes, {
        type = "input",
        name = "userCode" .. i,
        label = "User Code",
        description = "Enter a new user code for user " .. i .. ".",
        required = false,
        pattern = "%d%d%d%d%d?%d?",
      })
    -- Create a field for the user name
    table.insert(userCodes, {
        type = "input",
        name = "userName" .. i,
        label = "User Name",
        description = "Enter a name for user " .. i .. ".",
        required = false,
    })
    end

    -- Merge the user code preferences into the existing preferences table
    for _, userCode in ipairs(userCodes) do
    table.insert(preferences, userCode)
    end

    return preferences
end

-- .
-- . update_device
-- .
-- .
-- Handle device events and emit events for SmartThings to consume
local function update_device(driver, device, event)
    local event_type = event.type
  
    -- Handle lock/unlock events and panel lockout
    if event_type == zwave.CommandClass.NOTIFICATION then
      local alarm_type = event.args.notification_type
  
      -- Check if the lock has been locked by keypad, command, RF, or auto-lock
      if alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_KEYPAD or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_COMMAND or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_RF or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.LOCKED_BY_AUTO
      then
        device:emit_event(locks.locked())

      -- Check if the lock has been unlocked by keypad, command, or RF
      elseif alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_KEYPAD or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_COMMAND or
        alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.UNLOCKED_BY_RF
      then
        device:emit_event(locks.unlocked())

      -- Check if the lock is jammed
      elseif alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.JAMMED_LOCK then
        device:emit_event(locks.jammed())
        
      -- Check if panel lockout is enabled or disabled
      elseif alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.PANEL_LOCKOUT_ENABLED then
        device:emit_event(locks.panel_lockout_enabled())
      elseif alarm_type == zwave.Notification.TYPE.ACCESS_CONTROL.PANEL_LOCKOUT_DISABLED then
        device:emit_event(locks.panel_lockout_disabled())
      end

    -- Handle battery events
    elseif event_type == zwave.CommandClass.BATTERY then
      local battery_level = event.args.battery_level
      device:emit_event(battery.battery(battery_level))
    end
end



local yale_zwave_lock_driver = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.battery,
    capabilities.configuration,
    capabilities.healthCheck,
    capabilities.actuator,
    capabilities.sensor,
    capabilities.polling,
    capabilities.refresh,
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    event = device_event_handler,
  },
  command_handlers = {
    [capabilities.lock.commands.lock.NAME] = lock,
    [capabilities.lock.commands.unlock.NAME] = unlock,
    [capabilities.refresh.commands.refresh.NAME] = refresh,
    [capabilities.configuration.commands.configure.NAME] = configure,
  },
  preference_handlers = {
    updated = device_preferences,
  },
  is_compatible_with_device = is_yale_zwave_lock,
}

device_management.register_driver("yale_zwave_lock", yale_zwave_lock_driver)

return yale_zwave_lock_driver
