-- Execute actual addon in Lua5.0.3 with a deliberately limited Vanilla API mock.
local checks=0
local function check(value,label) checks=checks+1;if not value then error("FAIL "..label) end end
local objects={};local sent={};local clock=100;local roster={party1="Gatsu",party2="Cammy",party3="Arcee",party4="Escoria",target="Gatsu"}
local methods={}
function methods:SetWidth(v) self.width=v end
function methods:SetHeight(v) self.height=v end
function methods:SetPoint(...) self.point=arg end
function methods:GetPoint() return "CENTER",UIParent,"CENTER",0,0 end
function methods:ClearAllPoints() self.point=nil end
function methods:SetText(v) self.text=v end
function methods:GetText() return self.text end
function methods:SetAutoFocus(v) self.autofocus=v end
function methods:SetMaxLetters(v) self.maxletters=v end
function methods:ClearFocus() end
function methods:SetJustifyH(v) self.justify=v end
function methods:SetScript(key,v) self.scripts[key]=v end
function methods:RegisterEvent(key) self.events[key]=true end
function methods:SetFrameStrata(v) self.strata=v end
function methods:SetMovable(v) self.movable=v end
function methods:EnableMouse(v) self.mouse=v end
function methods:RegisterForDrag(v) self.drag=v end
function methods:SetClampedToScreen(v) self.clamped=v end
function methods:SetBackdrop(v) self.backdrop=v end
function methods:SetBackdropColor(...) end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:Enable() self.enabled=true end
function methods:Disable() self.enabled=false end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true;if self.scripts.OnShow then this=self;self.scripts.OnShow() end end
function methods:Hide() self.shown=false;if self.scripts.OnHide then this=self;self.scripts.OnHide() end end
function methods:SetOwner(...) end
function methods:CreateFontString(name,layer,font) local v=CreateFrame("Font",name,self);v.font=font;return v end
function CreateFrame(kind,name,parent,template)
    local value={kind=kind,name=name,parent=parent,template=template,scripts={},events={},enabled=true,shown=true}
    setmetatable(value,{__index=methods});table.insert(objects,value);if name then _G[name]=value end;return value
end
UIParent=CreateFrame("Frame","UIParent")
GameTooltip=CreateFrame("Frame","GameTooltip")
DEFAULT_CHAT_FRAME={AddMessage=function() end};SlashCmdList={}
function UnitExists(unit) return roster[unit]~=nil end
function UnitIsPlayer(unit) return roster[unit]~=nil end
function UnitName(unit) return roster[unit] end
function GetRealZoneText() return "Deadmines" end
function GetTime() return clock end
function time() return 1000 end
function SendChatMessage(text,channel,language,target) table.insert(sent,{text=text,target=target,channel=channel}) end
DungeonClearCMangosDB={shown=true,point="CENTER",x=11,y=22,untouched="retained"}
check(loadfile(arg[1])~=nil,"Lua5.0 syntax")
dofile(arg[1])
local events=DungeonClearCMangosEventFrame
local function eventCall(name,a,b) event=name;arg1=a;arg2=b;this=events;events.scripts.OnEvent() end
local function update() this=events;events.scripts.OnUpdate() end
local function click(button) this=button;button.scripts.OnClick() end
local function reply(request,state,tank,sender,kind,err,sessionOverride)
    local _,_,session,q=string.find(request.text,"^dc v1 (%d+) (%d+)")
    check(session~=nil,"request protocol preserved")
    local message="DC1|c="..(sessionOverride or session).."|q="..q.."|r=10|p=1/1|kind="..(kind or "status").."|ok="..(kind=="error" and "0" or "1").."|state="..state.."|run=1|idx=2|err="..(err or "NONE").."|g="..(tank and "1835" or "1836").."|it="..(tank and "1" or "0").."|ih="..(tank and "0" or "1")
    eventCall("CHAT_MSG_WHISPER",message,sender or request.target)
end
eventCall("VARIABLES_LOADED");eventCall("PLAYER_LOGIN")
check(DungeonClearCMangosFrame.width==420 and DungeonClearCMangosFrame.height==520,"compact dimensions")
check(not DungeonClearOnButton.enabled,"unconfirmed start disabled")
check(DungeonClearCMangosDB.untouched=="retained","unknown SavedVariables retained")
click(DungeonClearScanTankButton)
check(table.getn(sent)==4,"scan each party bot")
reply(sent[1],"IDLE",true);reply(sent[2],"BOSS_COMBAT",false)
reply(sent[3],"BOSS_COMBAT",false);reply(sent[4],"BOSS_COMBAT",false)
check(not DungeonClearOnButton.enabled,"companion state cannot authorize start")
clock=101;update();check(table.getn(sent)==5 and sent[5].target=="Gatsu","fresh selected tank status requested")
reply(sent[5],"IDLE",true,"Intruder")
check(not DungeonClearOnButton.enabled,"wrong sender rejected")
reply(sent[5],"IDLE",true,nil,nil,nil,"999")
check(not DungeonClearOnButton.enabled,"foreign session rejected")
reply(sent[5],"IDLE",true)
check(DungeonClearOnButton.enabled,"fresh tank IDLE start enabled")
check(not DungeonClearResumeButton.enabled and not DungeonClearPauseButton.enabled,"invalid idle controls disabled")
click(DungeonClearOnButton)
check(table.getn(sent)==6 and string.find(sent[6].text," on deadmines%.v1$"),"start request preserved")
check(not DungeonClearOnButton.enabled,"pending mutation disables start")
reply(sent[6],"COMBAT",true,nil,"ack")
clock=102;update();reply(sent[7],"COMBAT",true)
check(DungeonClearPauseButton.enabled and DungeonClearOffButton.enabled,"active controls enabled")
local count=table.getn(sent);click(DungeonClearOffButton)
check(table.getn(sent)==count,"stop first click does not send")
click(DungeonClearOffButton)
check(table.getn(sent)==count+1 and string.find(sent[count+1].text," off$"),"stop confirmed sends once")
reply(sent[count+1],"PAUSED",true,nil,"ack");clock=103;update();reply(sent[table.getn(sent)],"PAUSED",true)
check(DungeonClearResumeButton.enabled and not DungeonClearPauseButton.enabled,"paused controls reflect state")
count=table.getn(sent);click(DungeonClearSkipButton);clock=108;click(DungeonClearSkipButton)
check(table.getn(sent)==count,"expired confirmation cannot skip")
click(DungeonClearSkipButton);check(table.getn(sent)==count+1,"renewed confirmation skips once")
reply(sent[table.getn(sent)],"PAUSED",true,nil,"error","STALE_REVISION")
check(table.getn(sent)==count+1,"stale mutation never replayed")
clock=109;update();local last=sent[table.getn(sent)];reply(last,"PAUSED",true)
clock=130;update();check(not DungeonClearResumeButton.enabled,"stale status controls disabled")
click(DungeonClearStatusButton);count=table.getn(sent);clock=140;update()
check(table.getn(sent)==count,"timeout never replays command")
reply(sent[count],"COMBAT",true)
check(not DungeonClearPauseButton.enabled,"late expired response ignored")
click(DungeonClearDebugUiButton)
check(DungeonClearCMangosFrame.height==720 and DungeonClearCMangosDB.debugUiShown,"debug expanded persisted")
click(DungeonClearDebugUiButton);check(DungeonClearCMangosFrame.height==520,"debug collapsed")
SlashCmdList.DUNGEONCLEARCMANGOS("resetpos")
check(DungeonClearCMangosDB.point==nil and DungeonClearCMangosDB.x==0,"position reset")
roster.party2="Escoria";eventCall("PARTY_MEMBERS_CHANGED")
check(not DungeonClearOnButton.enabled and not DungeonClearStatusButton.enabled,"roster change invalidates tank")
roster.party2="Cammy";eventCall("PARTY_MEMBERS_CHANGED")
count=table.getn(sent);click(DungeonClearScanTankButton)
local i=1;while i<=4 do reply(sent[count+i],"IDLE",i==1);i=i+1 end
clock=141;update();reply(sent[table.getn(sent)],"IDLE",true)
check(DungeonClearOnButton.enabled,"tank reconfirmed")
click(DungeonClearRoutelistButton)
check(sent[table.getn(sent)].text=="dc route list","raw route namespace")
eventCall("CHAT_MSG_WHISPER","DC route id=intruder.v1 enabled=1 validated=1","Intruder")
eventCall("CHAT_MSG_WHISPER","DC route list result=PASS generation=1","Gatsu")
eventCall("CHAT_MSG_WHISPER","DC route id=deadmines.v1 enabled=1 validated=1","Gatsu")
eventCall("CHAT_MSG_WHISPER","DC route id=scarlet_monastery.graveyard.v1 enabled=0 validated=0","Gatsu")
click(DungeonClearRouteNextButton);check(DungeonClearRouteEdit:GetText()=="deadmines.v1","foreign route ignored")
click(DungeonClearRouteNextButton);check(DungeonClearRouteEdit:GetText()=="scarlet_monastery.graveyard.v1","selector uses server ids")
count=table.getn(sent);click(DungeonClearRoutevalidateButton)
check(table.getn(sent)==count,"route requests serialized")
clock=150;update();click(DungeonClearRoutevalidateButton)
check(sent[table.getn(sent)].text=="dc route validate scarlet_monastery.graveyard.v1","validation sent to authoritative server")
count=table.getn(sent)
DungeonClearRouteEdit:SetText("../outside");click(DungeonClearOnButton)
check(table.getn(sent)==count,"invalid route id cannot start")
DungeonClearRouteEdit:SetText("scarlet_monastery.graveyard.v1")
click(DungeonClearOnButton)
check(string.find(sent[table.getn(sent)].text,"on scarlet_monastery.graveyard.v1$"),"explicit selected route reaches server; disabled readiness enforced there")
reply(sent[table.getn(sent)],"IDLE",true,nil,"error","ROUTE_UNKNOWN")
check(DungeonClearOnButton.enabled,"server rejection releases pending command")
count=table.getn(sent);clock=160;update();click(DungeonClearRoutereloadButton)
check(sent[table.getn(sent)].text=="dc route reload scarlet_monastery.graveyard.v1","reload command explicit id")
eventCall("CHAT_MSG_WHISPER","DC route result=FAIL err=UNAUTHORIZED reason=admin","Gatsu")
check(table.getn(sent)==count+1,"route rejection not replayed")
print("ui checks="..checks.." failures=0")
