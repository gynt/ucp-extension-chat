


local convertStringToBytes = function(s)
  return table.pack(string.byte(s, 1, -1))
end

local convertStringToNullTerminatedBytes = function(s)
  local r = convertStringToBytes(s)
  table.insert(r, 0)
  return r
end


local startsWith = function(s, start)
  return string.sub(s, 1, string.len(start)) == start
end


local namespace

local _processFuncDetourLocationForChatMessageKeyReturn = core.AOBScan("89 ? ? ? ? ? E8 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 39 ? ? ? ? ?")
local _processFuncDetourSizeForChatMessageKeyReturn = 6

local _clickTauntOrChatInterestingLocation = core.AOBScan("8B ? ? ? ? ? 6A 00 52 B9 ? ? ? ? E8 ? ? ? ? 8B ? ? ? ? ? ?")

local _addChatMessageToDisplayList = core.exposeCode(core.AOBScan("53 56 8B F1 83 ? ? ? ? ? ? 8B ? ? ? ? ?"), 3, 1)
local MULTIPLAYER_HANDLER_ADDRESS = core.readInteger(_clickTauntOrChatInterestingLocation + 6 + 2 + 1 + 1)
local RECEIVED_CHAT_MESSAGE_ADDRESS = core.readInteger(core.AOBScan("BA ? ? ? ? 8A 08 88 0A 83 C0 01 83 C2 01 84 C9 75 F2 A1 ? ? ? ?") + 1)


local _activateModalDialog = core.exposeCode(core.AOBScan("53 55 33 ED 39 6C 24 10"), 3, 1)
local ACTIVE_MODAL_DIALOG_THIS_VALUE = core.readInteger(core.AOBScan("B9 ? ? ? ? 89 46 5C") + 1)


local processChatCommandDetourLocation = _clickTauntOrChatInterestingLocation + 6 + 2 + 1
local processChatCommandDetourSize = 5

local makeChatAvailableInAllGameModesLocation = core.AOBScan("75 5B 83 F9 FF")
local makeChatAvailableInAllGameModesNopCount = 2

local makeChatAvailableInAllGameModes2Location = core.AOBScan("75 0C 6A 79")

local makeReturnKeySendAChatInAllGameModes1Location = core.AOBScan("75 0D 83 F9 1B")
local makeReturnKeySendAChatInAllGameModes1NopCount = 2

local makeReturnKeySendAChatInAllGameModes2Location = core.AOBScan("75 0C 39 ? ? ? ? ? 0F ? ? ? ? ? 83 ? ? ? ? ? ? 0F ? ? ? ? ? B9 ? ? ? ?")

local preventAutomaticCloseOfChatModalLocation = core.AOBScan("53 6A FF B9 ? ? ? ? E8 ? ? ? ? E9 ? ? ? ?")
local preventAutomaticCloseOfChatModalNopCount = 13


local addChatMessageToDisplayList = function(subjectPlayerID, objectPlayerID)
  return _addChatMessageToDisplayList(MULTIPLAYER_HANDLER_ADDRESS, subjectPlayerID or 0, objectPlayerID or 0)
end


local fireChatEvent = function(text, subjectPlayerID, objectPlayerID)
  if text:len() > 249 then
    error("Chat message too long: " .. tostring(text))
  end
  local b = convertStringToNullTerminatedBytes(text)
  core.writeBytes(RECEIVED_CHAT_MESSAGE_ADDRESS, b) -- DAT_ReceivedChatMessage
  addChatMessageToDisplayList(subjectPlayerID or 0, objectPlayerID or 0)
end

local textHolder = core.allocate(250) -- 250 is the max text size of a text box
local USER_TEXT_HANDLER = core.readInteger(core.AOBScan("B9 ? ? ? ? E8 ? ? ? ? 8D ? ? ? ? ? ? 51 B9 ? ? ? ? E8 ? ? ? ? 83 ? ? ? ? ? ?") + 1)

-- local _setTextArrayIndex = core.exposeCode(core.AOBScan("33 D2 39 51 0C"), 2, 1)
-- local setTextArrayIndex = function(index)
--   if type(index) ~= "number" or index < 0 or index > 15 then error("Invalid text index: " .. tostring(index)) end
--   return _setTextArrayIndex(USER_TEXT_HANDLER, index)
-- end

local _getText = core.exposeCode(core.AOBScan("83 79 04 00 75 03"), 1, 1)
local function getText() return _getText(USER_TEXT_HANDLER) end

local _setCurrentTextBoxText = core.exposeCode(core.AOBScan("56 57 8B F1 E8 ? ? ? ? 8B 0E"), 2, 1)
local setCurrentTextBoxText = function(text)
  text = text:sub(1, 249)
  core.writeString(textHolder, text)
  core.writeByte(textHolder + text:len(), 0)
  return _setCurrentTextBoxText(USER_TEXT_HANDLER, textHolder)
end

local _clearCurrentText = core.exposeCode(core.AOBScan("56 8B F1 8B 06 69 ? ? ? ? ?"), 1, 1)
local clearCurrentText = function()
  return _clearCurrentText(USER_TEXT_HANDLER)
end


local activateModalDialog = function(modalMenuID, param_2)
    return _activateModalDialog(ACTIVE_MODAL_DIALOG_THIS_VALUE, modalMenuID, param_2)
end

local closeModalDialog = function()
  return activateModalDialog(-1, 0)
end

-- ordered table so extension order (priority) is preserved
local ChatHandlers = utils.OrderedTable:new()

local onChatMessage = function(chatMessage)

    local handled = false

    for header, handler in pairs(ChatHandlers) do
        if startsWith(chatMessage, header) and handled == false then
            handled = true
            local success, keepModalOpen, newMessage = pcall(handler, chatMessage)

            log(2, string.format("Handled command: %s, %s, %s", success, keepModalOpen, newMessage))

            if not success then
                local msg = "[chat]: error in processing command: " .. tostring(chatMessage) .. "\nerror: " .. tostring(keepModalOpen)
                log(WARNING, msg)


                -- TODO: replace with a fire chat event
--                core.writeBytes(RECEIVED_CHAT_MESSAGE_ADDRESS, convertStringToNullTerminatedBytes(msg)) -- DAT_ReceivedChatMessage
                fireChatEvent(msg, 0, 0)
                closeModalDialog() -- close the chat modal
            else
                if newMessage ~= nil then
   --               core.writeBytes(RECEIVED_CHAT_MESSAGE_ADDRESS, convertStringToNullTerminatedBytes(newMessage)) -- DAT_ReceivedChatMessage
                  fireChatEvent(newMessage, 0, 0)   
                end
                if not keepModalOpen then
                  closeModalDialog() -- close the chat modal
                end
            end

        end
    end

    return handled
end

local onChatWrapper1 = function(registers)
  onChatMessage(core.readString(RECEIVED_CHAT_MESSAGE_ADDRESS))

  return registers
end

local onChatWrapper2 = function(registers)
  local shouldSwallow = onChatMessage(core.readString(getText()))

  if shouldSwallow then
    core.writeInteger(registers.ESP, 0) -- zap out the queueCommand to point to the useless 0'th command
  end

  return registers
end

local NOPs = function(count)
  local ns = {}
  for i=1, count do
    table.insert(ns, 0x90)
  end
  return ns
end

-- int[9]
local CHAT_RECIPIENTS_ARRAY = core.readInteger(core.AOBScan("68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? A1 ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ?") + 22)
local CHAT_TAUNT_OR_CHAT_ADDRESS = core.readInteger(core.AOBScan("68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 68 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 50") + 1)

local setMessageIsChat = function()
  core.writeInteger(CHAT_TAUNT_OR_CHAT_ADDRESS, 0) -- magic value
end


namespace = {
  enable = function(self, config)
--     core.detourCode(onChat, processChatCommandDetourLocation, processChatCommandDetourSize)
    core.detourCode(onChatWrapper2, _processFuncDetourLocationForChatMessageKeyReturn, _processFuncDetourSizeForChatMessageKeyReturn)

    core.writeCode(makeChatAvailableInAllGameModesLocation, NOPs(makeChatAvailableInAllGameModesNopCount)) -- nop instructions to make chat available in all game modes.
    core.writeCode(makeChatAvailableInAllGameModes2Location, { 0xEB }) -- change a jnz to a jmp to display the chat window in single player games too!

    core.writeCode(makeReturnKeySendAChatInAllGameModes1Location, NOPs(makeReturnKeySendAChatInAllGameModes1NopCount)) -- nop instructions to make VK_RETURN send a chat in all game modes.
    core.writeCode(makeReturnKeySendAChatInAllGameModes2Location, { 0xEB }) -- change a jnz to a jmp to make VK_RETURN send a chat in all game modes.

    core.writeCode(preventAutomaticCloseOfChatModalLocation, NOPs(preventAutomaticCloseOfChatModalNopCount)) -- wipe 13 bytes to prevent automatic closing of chat modal

  end,
  disable = function(self)
  end,
  registerChatHandler = function(self, chatHeader, handler)
    if ChatHandlers[chatHeader] ~= nil then
      error("Failed to register chat handler. Chat handler already registered for header: " .. tostring(chatHeader))
    end

    ChatHandlers[chatHeader] = handler

    log(1, "Chat handler registered for header: " .. tostring(chatHeader))
  end,
  fireChatEvent = function(self, text, subjectPlayerID, objectPlayerID)
    return fireChatEvent(text, subjectPlayerID, objectPlayerID)
  end,
  sendChatMessage = function(self, message, recipients) 

    log(1, "Sending chat message: " .. tostring(message))

    setMessageIsChat()
    setCurrentTextBoxText(message)

    for i=0,8 do core.writeInteger(CHAT_RECIPIENTS_ARRAY + (4*i), 0) end

    for k, v in pairs(recipients) do
      if type(v) == "boolean" and type(k) == "number" and k < 9 and k >= 0 then
        core.writeInteger(CHAT_RECIPIENTS_ARRAY + (4 * k), 1)
      elseif type(v) == "number" and v < 9 and v >= 0 then
        core.writeInteger(CHAT_RECIPIENTS_ARRAY + (4 * v), 1)
      else
        error("Invalid recipient format: " .. tostring(k) .. " => " .. tostring(v))
      end
    end

    modules.protocol:queueCommand(0xE)
    clearCurrentText()
  end,
}

return namespace