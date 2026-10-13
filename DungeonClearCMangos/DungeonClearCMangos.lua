-- DungeonClearCMangos
-- DC-UI-R1
-- Vanilla WoW 1.12.1 / Interface 11200
--
-- Transport remains normal WHISPER because current PlayerBots intentionally
-- rejects CHAT_MSG_ADDON / LANG_ADDON as command input.
--
-- Wire protocol:
-- request:  dc v1 <session> <sequence> <expectedRevision> <verb> [arg]
-- reply:    DC1|c=...|q=...|r=...|p=1/1|kind=status|ack|error|... plus g/it/ih role metadata

DungeonClearCMangosDB = DungeonClearCMangosDB or {}

local DC = {}
DC.version = "0.7.0-routes-r1"
DC.targetName = nil
DC.selectedTankName = nil
DC.selectedTankGuid = nil
DC.lastCommand = "none"
DC.session = 0
DC.sequence = 0
DC.pending = {}
DC.revisionByTarget = {}
DC.protocolState = "tank scan required"
DC.runtimeState = "UNKNOWN"
DC.runtimeRun = "0"
DC.runtimeStep = "0"
DC.runtimeError = "UNKNOWN"
DC.commandError = "NONE"
DC.lastAck = "none"
DC.refreshAt = nil
DC.refreshTarget = nil
DC.refreshPurpose = nil
DC.partySignature = ""
DC.scanGeneration = 0
DC.scanActive = false
DC.scanExpected = 0
DC.scanWaiting = {}
DC.scanReplies = {}
DC.scanDeadline = nil
DC.debugUiShown = false
DC.controlButtons = {}
DC.lastStatusAt = nil
DC.confirmAction = nil
DC.confirmUntil = 0
DC.routeIds = {}
DC.routeCycle = 0
DC.routeResponse = "Rutas: sin respuesta del servidor"

local function DC_Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99DungeonClear|r: " .. tostring(text))
    end
end

local function DC_Trim(text)
    if not text then
        return ""
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function DC_IsDigits(text)
    if not text or text == "" then
        return false
    end
    local first, last = string.find(text, "^[0-9]+$")
    return first == 1 and last == string.len(text)
end

local function DC_GetTargetName()
    if UnitExists("target") and UnitIsPlayer("target") then
        return UnitName("target")
    end
    return nil
end

local function DC_GetZone()
    local zone = nil
    if GetRealZoneText then
        zone = GetRealZoneText()
    end
    if (not zone or zone == "") and GetZoneText then
        zone = GetZoneText()
    end
    if not zone or zone == "" then
        zone = "Unknown"
    end
    return zone
end

local function DC_GetRevision(target)
    if target and DC.revisionByTarget[target] then
        return DC.revisionByTarget[target]
    end
    return "0"
end

local function DC_CountTable(tableValue)
    local count = 0
    if not tableValue then
        return count
    end

    for key, value in pairs(tableValue) do
        if key ~= nil and value ~= nil then
            count = count + 1
        end
    end

    return count
end

local function DC_GetPartyNames()
    local names = {}
    local seen = {}
    local i = 1

    while i <= 4 do
        local unit = "party" .. tostring(i)
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
        i = i + 1
    end

    return names
end

local function DC_GetPartySignature()
    local names = DC_GetPartyNames()
    table.sort(names)
    return table.concat(names, ",")
end

local function DC_NameInParty(name)
    if not name then
        return false
    end

    local names = DC_GetPartyNames()
    local i = 1
    while i <= table.getn(names) do
        if names[i] == name then
            return true
        end
        i = i + 1
    end

    return false
end

local function DC_ControlAllowed(command)
    local confirmed = DC.selectedTankName and DC_NameInParty(DC.selectedTankName) and not DC.scanActive
    if not confirmed then return false end
    if command == "status" or command == "debug 1" then return true end
    if not DC.lastStatusAt or GetTime()-DC.lastStatusAt > 15 then return false end
    if DC_CountTable(DC.pending) > 0 then return false end
    local state=DC.runtimeState
    local active=state ~= "IDLE" and state ~= "UNKNOWN" and state ~= "COMPLETE" and state ~= "FAILED" and state ~= "PAUSED"
    if command == "on" then return state=="IDLE" or state=="COMPLETE" or state=="FAILED" end
    if command == "off" then return active or state=="PAUSED" or state=="FAILED" end
    if command == "pause" then return active end
    if command == "resume" then return state=="PAUSED" end
    if command == "retry" then return state=="FAILED" or state=="PAUSED" end
    if command == "skip" then return state=="PAUSED" end
    return false
end

local function DC_FriendlyError(err)
    local messages={PATH_INVALID="Ruta de movimiento no disponible",STUCK="El grupo no logra avanzar",GROUP_NOT_READY="Esperando al grupo",MISSING_REQUIRED_ITEM="Falta un objeto necesario",ROUTE_INVALID="Ruta rechazada por validacion",ROUTE_UNKNOWN="Ruta no disponible",WRONG_MAP="Instance incorrecta",UNAUTHORIZED="Sin permiso para esta accion",ACTION_TIMEOUT="La accion no respondio a tiempo"}
    return messages[err] or tostring(err)
end

local function DC_UpdateStaticLabels()
    if DC.zoneValue then
        DC.zoneValue:SetText(DC_GetZone())
    end

    if DC.targetValue then
        if DC.targetName then
            DC.targetValue:SetText(DC.targetName)
        else
            DC.targetValue:SetText("none")
        end
    end

    if DC.tankValue then
        if DC.selectedTankName then
            DC.tankValue:SetText("|cff33ff99" .. DC.selectedTankName .. " [server confirmed]|r")
        elseif DC.scanActive then
            DC.tankValue:SetText("|cffffff00scanning party...|r")
        else
            DC.tankValue:SetText("|cffff5555not confirmed - use SCAN TANK|r")
        end
    end

    if DC.lastValue then
        DC.lastValue:SetText(DC.lastCommand)
    end

    if DC.protocolValue then
        local revision = DC_GetRevision(DC.selectedTankName)
        DC.protocolValue:SetText(
            "session=" .. tostring(DC.session) ..
            "  rev=" .. tostring(revision) ..
            "  " .. tostring(DC.protocolState)
        )
    end

    local state=DC.runtimeState
    local color="|cffffff88"
    if state=="FAILED" then color="|cffff6666" elseif state=="COMPLETE" then color="|cff66ee99" elseif state=="PAUSED" then color="|cffffcc66" elseif state~="UNKNOWN" and state~="IDLE" then color="|cff66ccff" end
    if DC.runtimeValue then DC.runtimeValue:SetText(color..tostring(state).."|r") end
    if DC.progressValue then
        local index=tonumber(DC.runtimeStep)
        DC.progressValue:SetText(state=="COMPLETE" and "Recorrido completado" or (index and "Paso "..tostring(index+1) or "Paso sin datos"))
    end
    if DC.connectionValue then
        local fresh=DC.lastStatusAt and GetTime()-DC.lastStatusAt<=15
        DC.connectionValue:SetText(fresh and "|cff66ee99Servidor: respuesta reciente|r" or "|cffffff88Servidor: esperando estado|r")
    end
    if DC.runtimeErrorValue then
        DC.runtimeErrorValue:SetText(DC.runtimeError=="NONE" and "Sin error de ejecucion" or DC_FriendlyError(DC.runtimeError))
    end
    if DC.commandErrorValue then
        DC.commandErrorValue:SetText(DC.commandError=="NONE" and "" or DC_FriendlyError(DC.commandError))
    end
    for command,button in pairs(DC.controlButtons) do
        if DC_ControlAllowed(command) then button:Enable() else button:Disable() end
    end
    if DC.tankValue then
        DC.tankValue:SetText(DC.selectedTankName and "Tank: "..DC.selectedTankName.." (confirmado)" or "Tank: pendiente de confirmar")
    end

    if DC.routeResponseValue then DC.routeResponseValue:SetText(DC.routeResponse) end
    if DC.ackValue then
        DC.ackValue:SetText(DC.lastAck)
    end

    if DC.debugToggleButton then
        if DC.debugUiShown then
            DC.debugToggleButton:SetText("Ocultar diagnostico")
        else
            DC.debugToggleButton:SetText("Diagnostico")
        end
    end

    if DC.debugSessionValue then
        DC.debugSessionValue:SetText(
            "session=" .. tostring(DC.session) ..
            "  seq=" .. tostring(DC.sequence) ..
            "  pending=" .. tostring(DC_CountTable(DC.pending))
        )
    end

    if DC.debugTankValue then
        DC.debugTankValue:SetText(
            "tank=" .. tostring(DC.selectedTankName) ..
            "  guid=" .. tostring(DC.selectedTankGuid) ..
            "  rev=" .. tostring(DC_GetRevision(DC.selectedTankName))
        )
    end

    if DC.debugScanValue then
        DC.debugScanValue:SetText(
            "active=" .. tostring(DC.scanActive) ..
            "  gen=" .. tostring(DC.scanGeneration) ..
            "  waiting=" .. tostring(DC_CountTable(DC.scanWaiting)) ..
            "  replies=" .. tostring(DC_CountTable(DC.scanReplies))
        )
    end

    if DC.debugTargetValue then
        DC.debugTargetValue:SetText(
            "target=" .. tostring(DC.targetName) ..
            "  partySig=" .. tostring(DC.partySignature)
        )
    end

    if DC.debugProtocolValue then
        DC.debugProtocolValue:SetText(
            "protocol=" .. tostring(DC.protocolState) ..
            "  commandError=" .. tostring(DC.commandError)
        )
    end

    if DC.debugRuntimeValue then
        DC.debugRuntimeValue:SetText(
            "state=" .. tostring(DC.runtimeState) ..
            "  run=" .. tostring(DC.runtimeRun) ..
            "  step=" .. tostring(DC.runtimeStep) ..
            "  error=" .. tostring(DC.runtimeError)
        )
    end

    if DC.debugAckValue then
        DC.debugAckValue:SetText("ack=" .. tostring(DC.lastAck))
    end

    if DC.debugSentValue then
        DC.debugSentValue:SetText("sent=" .. tostring(DC.lastCommand))
    end
end

local function DC_SetDebugUiShown(shown)
    DC.debugUiShown = shown and true or false
    DungeonClearCMangosDB.debugUiShown = DC.debugUiShown

    if DC.frame then
        if DC.debugUiShown then
            DC.frame:SetHeight(720)
            if DC.debugFrame then
                DC.debugFrame:Show()
            end
        else
            if DC.debugFrame then
                DC.debugFrame:Hide()
            end
            DC.frame:SetHeight(520)
        end
    end

    DC_UpdateStaticLabels()
end

local function DC_SetTargetFromCurrent()
    DC.targetName = DC_GetTargetName()
    DC_UpdateStaticLabels()
end

local function DC_InvalidateTank(reason)
    DC.selectedTankName = nil
    DC.selectedTankGuid = nil
    DC.scanActive = false
    DC.scanWaiting = {}
    DC.scanReplies = {}
    DC.scanDeadline = nil
    DC.protocolState = reason or "tank scan required"
    DC_UpdateStaticLabels()
end

local function DC_GetConfirmedTank()
    if not DC.selectedTankName then
        return nil
    end

    if not DC_NameInParty(DC.selectedTankName) then
        DC_InvalidateTank("roster changed - scan required")
        return nil
    end

    return DC.selectedTankName
end

local function DC_NextSequence()
    DC.sequence = DC.sequence + 1
    if DC.sequence > 2147483647 then
        DC.sequence = 1
        DC.pending = {}
    end
    return DC.sequence
end

local function DC_SendRaw(command, targetOverride)
    if not targetOverride then
        DC_SetTargetFromCurrent()
    end

    local target = targetOverride or DC.targetName
    if not target then
        DC_Print("Target the PlayerBot that should receive the DungeonClear command.")
        return false
    end

    local text = "dc " .. command
    SendChatMessage(text, "WHISPER", nil, target)
    DC.lastCommand = text .. " -> " .. target
    DC.protocolState = "raw fallback"
    DC_UpdateStaticLabels()
    DC_Print("RAW sent " .. text .. " to " .. target)
    return true
end

local function DC_SendStructured(command, targetOverride, staleRetryCount, purpose, scanGeneration)
    local target = targetOverride or DC_GetConfirmedTank()
    if not target then
        DC_Print("No server-confirmed tank. Use /dc tank or SCAN TANK first.")
        return false
    end

    local sequence = DC_NextSequence()
    local revision = DC_GetRevision(target)
    local text =
        "dc v1 " ..
        tostring(DC.session) .. " " ..
        tostring(sequence) .. " " ..
        tostring(revision) .. " " ..
        command

    DC.pending[sequence] = {
        target = target,
        command = command,
        revision = revision,
        staleRetryCount = staleRetryCount or 0,
        purpose = purpose or "control",
        scanGeneration = scanGeneration or 0,
        sentAt = GetTime()
    }

    SendChatMessage(text, "WHISPER", nil, target)
    DC.lastCommand = text .. " -> " .. target

    if purpose ~= "tankscan" then
        DC.protocolState = "waiting q=" .. tostring(sequence)
    end

    DC_UpdateStaticLabels()
    DC_Print("v1 sent " .. command .. " to " .. target .. " q=" .. tostring(sequence) .. " r=" .. revision)
    return true
end

local function DC_ScheduleStatus(target, purpose)
    if not target then
        return
    end
    DC.refreshTarget = target
    DC.refreshPurpose = purpose or "verify"
    DC.refreshAt = GetTime() + 0.60
end

local function DC_ParseFields(message)
    if not message or string.sub(message, 1, 4) ~= "DC1|" then
        return nil
    end

    local fields = {}
    local position = 5
    local length = string.len(message)

    while position <= length do
        local separator = string.find(message, "|", position, true)
        local token = nil

        if separator then
            token = string.sub(message, position, separator - 1)
            position = separator + 1
        else
            token = string.sub(message, position)
            position = length + 1
        end

        local equals = string.find(token, "=", 1, true)
        if equals and equals > 1 then
            local key = string.sub(token, 1, equals - 1)
            local value = string.sub(token, equals + 1)
            fields[key] = value
        end
    end

    return fields
end

local function DC_ValidateEnvelope(fields, sender)
    if not fields then
        return nil, "not-dc1"
    end

    if not DC_IsDigits(fields["c"]) or tonumber(fields["c"]) ~= DC.session then
        return nil, "foreign-session"
    end

    if not DC_IsDigits(fields["q"]) then
        return nil, "bad-sequence"
    end

    local q = tonumber(fields["q"])
    local pending = DC.pending[q]
    if not pending then
        return nil, "unknown-or-stale-sequence"
    end

    if sender ~= pending.target then
        return nil, "wrong-sender"
    end

    if not fields["r"] or not DC_IsDigits(fields["r"]) then
        return nil, "bad-revision"
    end

    if fields["p"] ~= "1/1" then
        return nil, "unsupported-multipart"
    end

    if fields["kind"] ~= "status" and fields["kind"] ~= "ack" and fields["kind"] ~= "error" then
        return nil, "bad-kind"
    end

    if fields["ok"] ~= "0" and fields["ok"] ~= "1" then
        return nil, "bad-ok"
    end

    return pending, nil
end

local function DC_FinalizeTankScan(timedOut)
    if not DC.scanActive then
        return
    end

    local waitingCount = 0
    local name = nil
    for name in pairs(DC.scanWaiting) do
        waitingCount = waitingCount + 1
    end

    if waitingCount > 0 and not timedOut then
        return
    end

    DC.scanActive = false
    DC.scanDeadline = nil

    local replyCount = 0
    local validCount = 0
    local tankCount = 0
    local tankName = nil
    local tankGuid = nil
    local responder = nil

    for responder, result in pairs(DC.scanReplies) do
        replyCount = replyCount + 1
        if result.valid then
            validCount = validCount + 1
            if result.tank then
                tankCount = tankCount + 1
                tankName = responder
                tankGuid = result.guid
            end
        end
    end

    if replyCount == DC.scanExpected and
       validCount == DC.scanExpected and
       tankCount == 1 and
       tankName and DC_NameInParty(tankName) then
        DC.selectedTankName = tankName
        DC.selectedTankGuid = tankGuid
        DC.partySignature = DC_GetPartySignature()
        DC.protocolState = "tank confirmed"
        DC.runtimeState = "UNKNOWN"
        DC.lastStatusAt = nil
        DC_ScheduleStatus(tankName, "verify")
        DC_Print("Tank controller confirmed by server: " .. tankName .. " guid=" .. tostring(tankGuid))
    else
        DC.selectedTankName = nil
        DC.selectedTankGuid = nil
        DC.protocolState = "tank scan failed"
        if timedOut then
            DC_Print("Tank scan FAILED: timeout or missing PlayerBot response. No tank selected.")
        else
            DC_Print(
                "Tank scan FAILED: replies=" .. tostring(replyCount) ..
                "/" .. tostring(DC.scanExpected) ..
                " valid=" .. tostring(validCount) ..
                " tanks=" .. tostring(tankCount) ..
                ". No tank selected."
            )
        end
    end

    DC.scanWaiting = {}
    DC_UpdateStaticLabels()
end

local function DC_RecordTankScanStatus(fields, sender, pending)
    if not DC.scanActive or
       pending.purpose ~= "tankscan" or
       pending.scanGeneration ~= DC.scanGeneration or
       not DC.scanWaiting[sender] then
        return
    end

    local valid =
        fields["g"] and DC_IsDigits(fields["g"]) and fields["g"] ~= "0" and
        (fields["it"] == "0" or fields["it"] == "1") and
        (fields["ih"] == "0" or fields["ih"] == "1")

    DC.scanReplies[sender] = {
        valid = valid and true or false,
        guid = fields["g"],
        tank = fields["it"] == "1",
        healer = fields["ih"] == "1"
    }
    DC.scanWaiting[sender] = nil

    if valid then
        DC_Print(
            "tank scan " .. sender ..
            " tank=" .. tostring(fields["it"]) ..
            " healer=" .. tostring(fields["ih"]) ..
            " guid=" .. tostring(fields["g"])
        )
    else
        DC_Print("tank scan " .. sender .. " returned invalid/missing role metadata")
    end

    DC_FinalizeTankScan(false)
end

local function DC_RecordTankScanError(sender, pending, err)
    if not DC.scanActive or
       pending.purpose ~= "tankscan" or
       pending.scanGeneration ~= DC.scanGeneration or
       not DC.scanWaiting[sender] then
        return
    end

    DC.scanReplies[sender] = {
        valid = false,
        error = err
    }
    DC.scanWaiting[sender] = nil
    DC_Print("tank scan " .. sender .. " error=" .. tostring(err))
    DC_FinalizeTankScan(false)
end

local function DC_BeginTankScan()
    local names = DC_GetPartyNames()
    local count = table.getn(names)

    DC.scanGeneration = DC.scanGeneration + 1
    DC.scanActive = false
    DC.scanExpected = count
    DC.scanWaiting = {}
    DC.scanReplies = {}
    DC.scanDeadline = nil
    DC.selectedTankName = nil
    DC.selectedTankGuid = nil

    if count ~= 4 then
        DC.protocolState = "tank scan failed"
        DC_Print("Tank scan requires the V1 roster: Luigi + exactly four party members. Found " .. tostring(count) .. ".")
        DC_UpdateStaticLabels()
        return false
    end

    DC.scanActive = true
    DC.scanExpected = count
    DC.scanDeadline = GetTime() + 5.0
    DC.protocolState = "scanning tank"

    local i = 1
    while i <= count do
        DC.scanWaiting[names[i]] = true
        i = i + 1
    end

    DC_UpdateStaticLabels()
    DC_Print("Scanning " .. tostring(count) .. " party members for the server-confirmed tank...")

    i = 1
    while i <= count do
        if not DC_SendStructured("status", names[i], 0, "tankscan", DC.scanGeneration) then
            DC.scanReplies[names[i]] = { valid = false, error = "SEND_FAILED" }
            DC.scanWaiting[names[i]] = nil
        end
        i = i + 1
    end

    DC_FinalizeTankScan(false)
    return true
end

local function DC_AcceptStatus(fields, sender, pending)
    local state = fields["state"] or "?"
    local run = fields["run"] or "?"
    local idx = fields["idx"] or "?"
    local err = fields["err"] or "?"

    if pending.purpose ~= "tankscan" and sender == DC.selectedTankName then
        DC.runtimeState = state
        DC.runtimeRun = run
        DC.runtimeStep = idx
        DC.runtimeError = err
        DC.lastStatusAt = GetTime()
        DC.confirmAction = nil
    end

    if pending.purpose == "tankscan" then
        DC_RecordTankScanStatus(fields, sender, pending)
    else
        DC.protocolState = "synced"
    end

    DC_Print(
        "STATUS " .. sender ..
        " state=" .. state ..
        " run=" .. run ..
        " step=" .. idx ..
        " revision=" .. fields["r"] ..
        " runtimeError=" .. err
    )
end

local function DC_HandleProtocolWhisper(message, sender)
    local fields = DC_ParseFields(message)
    if not fields then
        return false
    end

    local pending, reason = DC_ValidateEnvelope(fields, sender)
    if not pending then
        -- DC1 traffic for another session/old sequence is deliberately ignored.
        return true
    end

    local q = tonumber(fields["q"])
    DC.pending[q] = nil
    DC.revisionByTarget[sender] = fields["r"]

    if fields["kind"] == "status" and fields["ok"] == "1" then
        DC_AcceptStatus(fields, sender, pending)
        DC_UpdateStaticLabels()
        return true
    end

    if fields["kind"] == "ack" and fields["ok"] == "1" then
        local cmd = fields["cmd"] or pending.command
        DC.protocolState = "ACK " .. tostring(cmd)
        DC.lastAck = tostring(cmd) .. " @ revision " .. tostring(fields["r"])
        DC.commandError = "NONE"
        DC_UpdateStaticLabels()
        DC_Print("ACK " .. tostring(cmd) .. " from " .. sender .. "; verifying runtime status")
        DC_ScheduleStatus(sender, "verify")
        return true
    end

    if fields["kind"] == "error" then
        local err = fields["err"] or "UNKNOWN"

        if err == "STALE_REVISION" and pending.command == "status" and pending.staleRetryCount < 1 then
            DC.protocolState = "resyncing revision"
            DC_UpdateStaticLabels()
            DC_Print("revision resync " .. sender .. " -> " .. fields["r"] .. "; retrying STATUS")
            DC_SendStructured(
                "status",
                sender,
                pending.staleRetryCount + 1,
                pending.purpose,
                pending.scanGeneration
            )
        else
            DC.protocolState = "ERROR " .. err
            DC.commandError = err .. " [" .. tostring(pending.command) .. "]"
            DC_UpdateStaticLabels()

            if err == "STALE_REVISION" then
                DC_Print("STALE_REVISION; revision updated to " .. fields["r"] .. ". Command was NOT replayed.")
                if pending.purpose == "tankscan" then
                    DC_RecordTankScanError(sender, pending, err)
                elseif pending.command ~= "status" then
                    DC_ScheduleStatus(sender, "verify")
                end
            else
                if pending.purpose == "tankscan" then
                    DC_RecordTankScanError(sender, pending, err)
                end
                DC_Print("command/protocol error from " .. sender .. ": " .. err .. " command=" .. tostring(pending.command))
            end
        end

        return true
    end

    return true
end

-- Raw route commands have no sequence envelope. Replies are advisory display
-- only; they never authorize execution or assert the active run's route.
local function DC_RouteIdValid(id)
    return id and string.len(id)>0 and string.len(id)<=48 and string.find(id,"^[a-z0-9][a-z0-9_.-]*$")~=nil
end

local function DC_SelectedRoute()
    local id=DC.routeEdit and DC_Trim(DC.routeEdit:GetText()) or "deadmines.v1"
    if not DC_RouteIdValid(id) then return nil end
    return id
end

local function DC_SendRoute(verb)
    local target=DC_GetConfirmedTank()
    if not target then DC_Print("Confirma el tank antes de consultar rutas.");return false end
    if DC.routePending and GetTime()<DC.routePending.deadline then
        DC_Print("Espera la respuesta de rutas.");return false
    end
    local id=DC_SelectedRoute()
    if verb~="list" and not id then DC_Print("Route id invalido.");return false end
    if verb~="list" and verb~="show" and verb~="validate" and verb~="reload" then return false end
    DC.routePending={target=target,verb=verb,id=id,deadline=GetTime()+8}
    if verb=="list" then DC.routeIds={};DC.routeCycle=0 end
    DC.routeResponse="Esperando "..verb.."..."
    DC_SendRaw("route "..verb..(verb=="list" and "" or " "..id),target)
    return true
end

local function DC_HandleRouteWhisper(message,sender)
    if not message or string.sub(message,1,9)~="DC route " then return false end
    local pending=DC.routePending
    if not pending or sender~=pending.target or sender~=DC.selectedTankName or GetTime()>pending.deadline then return true end
    local _,_,id=string.find(message,"^DC route id=([a-z0-9_.-]+)")
    if id and pending.verb~="list" and id~=pending.id then return true end
    if id and pending.verb=="list" and DC_RouteIdValid(id) then
        local found=false;local i=1
        while i<=table.getn(DC.routeIds) do if DC.routeIds[i]==id then found=true end;i=i+1 end
        if not found and table.getn(DC.routeIds)<32 then table.insert(DC.routeIds,id) end
    end
    -- Keep exact raw evidence in local diagnostics/chat; do not infer active
    -- route identity, step totals, validation freshness or runnable permission.
    DC.routeResponse=string.sub(message,1,220)
    pending.responseSeen=true
    DC_Print(DC.routeResponse)
    DC_UpdateStaticLabels()
    return true
end
local function DC_SavePosition(frame)
    if not frame then
        return
    end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    DungeonClearCMangosDB.point = point or "CENTER"
    DungeonClearCMangosDB.relativePoint = relativePoint or DungeonClearCMangosDB.point
    DungeonClearCMangosDB.x = x or 0
    DungeonClearCMangosDB.y = y or 0
end

local function DC_RestorePosition(frame)
    frame:ClearAllPoints()

    if DungeonClearCMangosDB.point then
        frame:SetPoint(
            DungeonClearCMangosDB.point,
            UIParent,
            DungeonClearCMangosDB.relativePoint or DungeonClearCMangosDB.point,
            DungeonClearCMangosDB.x or 0,
            DungeonClearCMangosDB.y or 0
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function DC_MakeButton(parent, name, text, width, x, y, command)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button.command = command
    DC.controlButtons[command]=button
    button:SetScript("OnEnter",function()
        GameTooltip:SetOwner(this,"ANCHOR_RIGHT")
        GameTooltip:SetText(this.command.." - requiere tank confirmado y estado reciente. Detener/saltar: pulsa dos veces.")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function()
        local command=this.command
        if not DC_ControlAllowed(command) then return end
        if command=="off" or command=="skip" then
            if DC.confirmAction~=command or GetTime()>DC.confirmUntil then
                DC.confirmAction=command; DC.confirmUntil=GetTime()+4
                DC.commandError="Pulsa otra vez en 4 segundos para confirmar "..command
                DC_UpdateStaticLabels(); return
            end
            DC.confirmAction=nil
        end
        DC.commandError="NONE"
        if command=="on" then
            local route=DC_SelectedRoute()
            if not route then DC_Print("Route id invalido.");return end
            command="on "..route
        end
        DC_SendStructured(command)
    end)
    return button
end

-- Vanilla frame construction; runtime/protocol remain authoritative on the server.
local function DC_CreateFrame()
    if DC.frame then return end
    local frame = CreateFrame("Frame", "DungeonClearCMangosFrame", UIParent)
    DC.frame = frame
    frame:SetWidth(420)
    frame:SetHeight(DC.debugUiShown and 720 or 520)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(0.04,0.06,0.09,0.96)
    frame:SetScript("OnDragStart",function() this:StartMoving() end)
    frame:SetScript("OnDragStop",function() this:StopMovingOrSizing(); DC_SavePosition(this) end)
    frame:SetScript("OnShow",function() DungeonClearCMangosDB.shown=true; DC_SetTargetFromCurrent(); DC_UpdateStaticLabels() end)
    frame:SetScript("OnHide",function() DungeonClearCMangosDB.shown=false end)
    DC_RestorePosition(frame)
    local function label(y,font,text)
        local value=frame:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT",frame,"TOPLEFT",20,y)
        value:SetWidth(380);value:SetJustifyH("LEFT")
        if text then value:SetText(text) end
        return value
    end
    label(-18,"GameFontNormalLarge","DungeonClear")
    DC.zoneValue=label(-43,nil)
    DC.runtimeValue=label(-72,"GameFontNormalLarge")
    DC.tankValue=label(-105,"GameFontHighlight")
    DC.progressValue=label(-130,"GameFontHighlight")
    DC.connectionValue=label(-153,nil)
    DC.runtimeErrorValue=label(-180,"GameFontHighlight")
    DC.runtimeErrorValue:SetHeight(34)
    DC.commandErrorValue=label(-217,nil)
    DC.commandErrorValue:SetHeight(30)
    label(-258,"GameFontNormal","Controles")
    DC_MakeButton(frame,"DungeonClearOnButton","Iniciar",120,20,-280,"on")
    DC_MakeButton(frame,"DungeonClearPauseButton","Pausar",120,150,-280,"pause")
    DC_MakeButton(frame,"DungeonClearResumeButton","Reanudar",120,280,-280,"resume")
    DC_MakeButton(frame,"DungeonClearOffButton","Detener",120,20,-310,"off")
    DC_MakeButton(frame,"DungeonClearRetryButton","Reintentar",120,150,-310,"retry")
    DC_MakeButton(frame,"DungeonClearStatusButton","Actualizar",120,280,-310,"status")
    local scan=CreateFrame("Button","DungeonClearScanTankButton",frame,"UIPanelButtonTemplate")
    scan:SetWidth(185);scan:SetHeight(23);scan:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-345);scan:SetText("Confirmar tank")
    scan:SetScript("OnClick",function() DC_BeginTankScan() end)
    local debug=CreateFrame("Button","DungeonClearDebugUiButton",frame,"UIPanelButtonTemplate")
    DC.debugToggleButton=debug
    debug:SetWidth(185);debug:SetHeight(23);debug:SetPoint("TOPLEFT",frame,"TOPLEFT",215,-345)
    debug:SetScript("OnClick",function() DC_SetDebugUiShown(not DC.debugUiShown) end)
    DC.routeSlot=CreateFrame("Frame",nil,frame)
    DC.routeSlot:SetWidth(380);DC.routeSlot:SetHeight(120);DC.routeSlot:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-380)
    local hint=DC.routeSlot:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT",DC.routeSlot,"TOPLEFT",0,0);hint:SetWidth(380);hint:SetJustifyH("LEFT")
    hint:SetText("Seleccion de ruta (el servidor valida al iniciar)")
    DC.routeHint=hint
    local edit=CreateFrame("EditBox","DungeonClearRouteEdit",DC.routeSlot,"InputBoxTemplate")
    DC.routeEdit=edit;edit:SetWidth(275);edit:SetHeight(22);edit:SetPoint("TOPLEFT",DC.routeSlot,"TOPLEFT",5,-20)
    edit:SetAutoFocus(false);edit:SetMaxLetters(48)
    local saved=DungeonClearCMangosDB.selectedRoute
    edit:SetText(DC_RouteIdValid(saved) and saved or "deadmines.v1")
    edit:SetScript("OnEnterPressed",function() this:ClearFocus() end)
    edit:SetScript("OnEscapePressed",function() this:ClearFocus() end)
    edit:SetScript("OnTextChanged",function()
        local id=DC_Trim(this:GetText())
        if DC_RouteIdValid(id) then DungeonClearCMangosDB.selectedRoute=id end
    end)
    local cycle=CreateFrame("Button","DungeonClearRouteNextButton",DC.routeSlot,"UIPanelButtonTemplate")
    cycle:SetWidth(90);cycle:SetHeight(22);cycle:SetPoint("TOPLEFT",DC.routeSlot,"TOPLEFT",290,-20);cycle:SetText("Siguiente")
    cycle:SetScript("OnClick",function()
        if table.getn(DC.routeIds)==0 then DC_SendRoute("list");return end
        DC.routeCycle=DC.routeCycle+1
        if DC.routeCycle>table.getn(DC.routeIds) then DC.routeCycle=1 end
        DC.routeEdit:SetText(DC.routeIds[DC.routeCycle])
        DungeonClearCMangosDB.selectedRoute=DC.routeIds[DC.routeCycle]
    end)
    local verbs={"list","show","validate","reload"}
    local labels={"Listar","Ver","Validar","Recargar"}
    local i=1
    while i<=4 do
        local b=CreateFrame("Button","DungeonClearRoute"..verbs[i].."Button",DC.routeSlot,"UIPanelButtonTemplate")
        b:SetWidth(90);b:SetHeight(22);b:SetPoint("TOPLEFT",DC.routeSlot,"TOPLEFT",(i-1)*97,-49);b:SetText(labels[i]);b.routeVerb=verbs[i]
        b:SetScript("OnClick",function() DC_SendRoute(this.routeVerb) end)
        b:SetScript("OnEnter",function() GameTooltip:SetOwner(this,"ANCHOR_RIGHT");GameTooltip:SetText("Servidor: route "..this.routeVerb..". Recargar requiere permiso GM y conserva runs activas.");GameTooltip:Show() end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        i=i+1
    end
    DC.routeResponseValue=DC.routeSlot:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    DC.routeResponseValue:SetPoint("TOPLEFT",DC.routeSlot,"TOPLEFT",0,-78);DC.routeResponseValue:SetWidth(380);DC.routeResponseValue:SetHeight(38);DC.routeResponseValue:SetJustifyH("LEFT")
    local panel=CreateFrame("Frame",nil,frame)
    DC.debugFrame=panel
    panel:SetWidth(380);panel:SetHeight(200);panel:SetPoint("TOPLEFT",frame,"TOPLEFT",20,-520)
    local fields={"debugSessionValue","debugTankValue","debugScanValue","debugTargetValue","debugProtocolValue","debugRuntimeValue","debugAckValue","debugSentValue"}
    local i=1
    while i<=table.getn(fields) do
        local value=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        value:SetPoint("TOPLEFT",panel,"TOPLEFT",0,-(i-1)*19);value:SetWidth(380);value:SetJustifyH("LEFT")
        DC[fields[i]]=value;i=i+1
    end
    DC_MakeButton(panel,"DungeonClearSkipButton","Saltar (avanzado)",185,0,-158,"skip")
    DC_MakeButton(panel,"DungeonClearDebugButton","Diagnostico server",185,195,-158,"debug 1")
    local close=CreateFrame("Button","DungeonClearCloseButton",frame,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-3,-3)
    if DC.debugUiShown then panel:Show() else panel:Hide() end
    DC_UpdateStaticLabels()
end

local function DC_Show()
    DC_CreateFrame()
    DC.frame:Show()
end

local function DC_Hide()
    if DC.frame then
        DC.frame:Hide()
    end
end

local function DC_Toggle()
    DC_CreateFrame()
    if DC.frame:IsVisible() then
        DC.frame:Hide()
    else
        DC.frame:Show()
    end
end

local function DC_Help()
    DC_Print("/dc - toggle panel")
    DC_Print("/dc show | hide")
    DC_Print("/dc tank - scan party roster and confirm exactly one server-side tank")
    DC_Print("/dc on [route] | off | pause | resume | skip | retry | status | debug [0|1]")
    DC_Print("/dc raw <command> - unversioned fallback to CURRENT WoW target")
    DC_Print("/dc proto - show protocol/tank/target state")
    DC_Print("/dc debugui - toggle the local P034 diagnostic panel")
end

local function DC_InitSession()
    local seed = 12345
    if time then
        seed = time()
    end
    if GetTime then
        seed = seed + math.floor(GetTime() * 1000)
    end

    math.randomseed(seed)
    math.random()
    math.random()

    DC.session = math.random(100000, 1000000000)
    DC.sequence = 0
    DC.pending = {}
    DC.revisionByTarget = {}
    DC.protocolState = "tank scan required"
    DC.runtimeState = "UNKNOWN"
    DC.runtimeRun = "0"
    DC.runtimeStep = "0"
    DC.runtimeError = "UNKNOWN"
    DC.commandError = "NONE"
    DC.lastAck = "none"
    DC.refreshAt = nil
    DC.refreshTarget = nil
    DC.refreshPurpose = nil
    DC.selectedTankName = nil
    DC.selectedTankGuid = nil
    DC.scanGeneration = 0
    DC.scanActive = false
    DC.scanExpected = 0
    DC.scanWaiting = {}
    DC.scanReplies = {}
    DC.scanDeadline = nil
    DC.partySignature = DC_GetPartySignature()
    DC.debugUiShown = DungeonClearCMangosDB.debugUiShown == true
end

SLASH_DUNGEONCLEARCMANGOS1 = "/dc"
SlashCmdList["DUNGEONCLEARCMANGOS"] = function(msg)
    msg = DC_Trim(msg)

    if msg == "" then
        DC_Toggle()
        return
    end

    local first = msg
    local rest = ""
    local space = string.find(msg, "%s")
    if space then
        first = string.sub(msg, 1, space - 1)
        rest = DC_Trim(string.sub(msg, space + 1))
    end

    first = string.lower(first)

    if first == "show" then
        DC_Show()
        return
    elseif first == "hide" then
        DC_Hide()
        return
    elseif first == "help" then
        DC_Help()
        return
    elseif first == "tank" then
        DC_BeginTankScan()
        return
    elseif first == "proto" then
        DC_SetTargetFromCurrent()
        DC_Print(
            "session=" .. tostring(DC.session) ..
            " sequence=" .. tostring(DC.sequence) ..
            " currentTarget=" .. tostring(DC.targetName) ..
            " tank=" .. tostring(DC.selectedTankName) ..
            " tankGuid=" .. tostring(DC.selectedTankGuid) ..
            " revision=" .. DC_GetRevision(DC.selectedTankName) ..
            " protocol=" .. tostring(DC.protocolState) ..
            " pending=" .. tostring(DC_CountTable(DC.pending)) ..
            " runtime=" .. tostring(DC.runtimeState) ..
            " runtimeError=" .. tostring(DC.runtimeError) ..
            " commandError=" .. tostring(DC.commandError) ..
            " debugUi=" .. tostring(DC.debugUiShown)
        )
        return
    elseif first == "debugui" then
        DC_SetDebugUiShown(not DC.debugUiShown)
        DC_Print("Debug UI " .. (DC.debugUiShown and "enabled" or "disabled"))
        return
    elseif first == "route" then
        local _,_,verb,id=string.find(rest,"^(%a+)%s*([a-z0-9_.-]*)$")
        if id and id~="" and DC.routeEdit then DC.routeEdit:SetText(id) end
        DC_SendRoute(verb)
        return
    elseif first == "resetpos" then
        DungeonClearCMangosDB.point=nil
        DungeonClearCMangosDB.relativePoint=nil
        DungeonClearCMangosDB.x=0;DungeonClearCMangosDB.y=0
        if DC.frame then DC_RestorePosition(DC.frame) end
        return
    elseif first == "raw" then
        if rest == "" then
            DC_Print("usage: /dc raw <command>")
        else
            DC_SendRaw(rest)
        end
        return
    elseif first == "on" then
        if rest ~= "" then
            DC_SendStructured("on " .. rest)
        else
            DC_SendStructured("on")
        end
        return
    elseif first == "debug" then
        if rest == "0" or rest == "1" then
            DC_SendStructured("debug " .. rest)
        else
            DC_SendStructured("debug 1")
        end
        return
    elseif first == "off" or
           first == "pause" or
           first == "resume" or
           first == "skip" or
           first == "retry" or
           first == "status" then
        DC_SendStructured(first)
        return
    end

    DC_Print("Unknown command: " .. msg)
    DC_Help()
end

local eventFrame = CreateFrame("Frame", "DungeonClearCMangosEventFrame", UIParent)
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")

eventFrame:SetScript("OnUpdate", function()
    for q,pending in pairs(DC.pending) do
        if pending.sentAt and GetTime()-pending.sentAt>8 then
            DC.pending[q]=nil
            if pending.purpose~="tankscan" then
                DC.commandError="Sin respuesta: "..pending.command..". Actualiza estado; accion no repetida."
            end
        end
    end
    if DC.routePending and GetTime()>DC.routePending.deadline then
        if not DC.routePending.responseSeen then DC.routeResponse="Rutas: sin respuesta; consulta otra vez. Accion no repetida." end
        DC.routePending=nil
    end
    if DC.frame and DC.frame:IsShown() then DC_UpdateStaticLabels() end
    if DC.refreshAt and GetTime() >= DC.refreshAt then
        local target = DC.refreshTarget
        local purpose = DC.refreshPurpose
        DC.refreshAt = nil
        DC.refreshTarget = nil
        DC.refreshPurpose = nil
        DC_SendStructured("status", target, 0, purpose or "verify", 0)
    end

    if DC.scanActive and DC.scanDeadline and GetTime() >= DC.scanDeadline then
        DC_FinalizeTankScan(true)
    end
end)

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if not DungeonClearCMangosDB then
            DungeonClearCMangosDB = {}
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        DC_InitSession()
        DC_CreateFrame()

        if DungeonClearCMangosDB.shown == false then
            DC.frame:Hide()
        else
            DC.frame:Show()
        end

        DC_Print("UI actualizada. Confirma el tank y actualiza estado antes de iniciar.")
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        DC_SetTargetFromCurrent()
        return
    end

    if event == "PARTY_MEMBERS_CHANGED" then
        local signature = DC_GetPartySignature()
        if DC.partySignature ~= "" and signature ~= DC.partySignature then
            DC.partySignature = signature
            DC_InvalidateTank("roster changed - scan required")
            DC_Print("Party roster changed. Tank confirmation invalidated; run /dc tank again.")
        else
            DC.partySignature = signature
        end
        return
    end

    if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        DC_UpdateStaticLabels()
        return
    end

    if event == "CHAT_MSG_WHISPER" then
        if DC_HandleRouteWhisper(arg1, arg2) then return end
        if DC_HandleProtocolWhisper(arg1, arg2) then
            return
        end
        return
    end
end)