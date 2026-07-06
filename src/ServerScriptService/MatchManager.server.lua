local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage:WaitForChild("NetworkBootstrap"))

local MATCH_DURATION_SECONDS = 300
local SCORE_PER_SECOND = 1
local CARRIER_SPEED_MULTIPLIER = 0.8
local AURA_RADIUS_STUDS = 25

local matchState = {
	RemainingSeconds = MATCH_DURATION_SECONDS,
	Scores = {
		Blue = 0,
		Red = 0,
	},
	Winner = nil,
}

local originalWalkSpeedByUserId = {}
local activeCarrierUserId = nil
local elapsedScoreTime = 0
local elapsedClockTime = 0

local function getCore()
	local cores = CollectionService:GetTagged("MatchCore")
	return cores[1]
end

local function getCarrier(core)
	local carrierUserId = core and core:GetAttribute("CarrierUserId")
	if typeof(carrierUserId) ~= "number" then
		return nil
	end

	return Players:GetPlayerByUserId(carrierUserId)
end

local function getCarrierTeam(core, carrier)
	local teamName = core and core:GetAttribute("CarrierTeam")
	if typeof(teamName) == "string" and matchState.Scores[teamName] ~= nil then
		return teamName
	end

	if carrier and carrier.Team then
		return carrier.Team.Name
	end

	return nil
end

local clearCarrierDebuff

local function setCarrierDebuff(carrier)
	if activeCarrierUserId == carrier.UserId then
		return
	end

	clearCarrierDebuff()
	activeCarrierUserId = carrier.UserId
	local humanoid = carrier.Character and carrier.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	originalWalkSpeedByUserId[carrier.UserId] = originalWalkSpeedByUserId[carrier.UserId] or humanoid.WalkSpeed
	humanoid.WalkSpeed = originalWalkSpeedByUserId[carrier.UserId] * CARRIER_SPEED_MULTIPLIER
end

clearCarrierDebuff = function()
	if not activeCarrierUserId then
		return
	end

	local carrier = Players:GetPlayerByUserId(activeCarrierUserId)
	local originalSpeed = originalWalkSpeedByUserId[activeCarrierUserId]
	local humanoid = carrier and carrier.Character and carrier.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and originalSpeed then
		humanoid.WalkSpeed = originalSpeed
	end

	activeCarrierUserId = nil
end

local function getCorePosition(core)
	if not core then
		return nil
	end

	if core:IsA("BasePart") then
		return core.Position
	end

	if core:IsA("Model") then
		return core:GetPivot().Position
	end

	return nil
end

local function publishState(core, carrier, carrierTeam)
	Network.MatchStateUpdate:FireAllClients({
		RemainingSeconds = math.max(0, math.ceil(matchState.RemainingSeconds)),
		Scores = matchState.Scores,
		Winner = matchState.Winner,
		CarrierUserId = carrier and carrier.UserId or nil,
		CarrierTeam = carrierTeam,
		AuraRadiusStuds = AURA_RADIUS_STUDS,
		CorePosition = getCorePosition(core),
	})
end

RunService.Heartbeat:Connect(function(deltaTime)
	if matchState.Winner then
		return
	end

	local core = getCore()
	local carrier = getCarrier(core)
	local carrierTeam = getCarrierTeam(core, carrier)

	matchState.RemainingSeconds -= deltaTime
	elapsedClockTime += deltaTime
	elapsedScoreTime += deltaTime

	if carrier and carrierTeam then
		setCarrierDebuff(carrier)
		while elapsedScoreTime >= 1 do
			elapsedScoreTime -= 1
			matchState.Scores[carrierTeam] = math.min(100, matchState.Scores[carrierTeam] + SCORE_PER_SECOND)
		end
	else
		clearCarrierDebuff()
		elapsedScoreTime = 0
	end

	for teamName, score in pairs(matchState.Scores) do
		if score >= 100 then
			matchState.Winner = teamName
		end
	end

	if matchState.RemainingSeconds <= 0 and not matchState.Winner then
		matchState.Winner = matchState.Scores.Blue >= matchState.Scores.Red and "Blue" or "Red"
	end

	if elapsedClockTime >= 1 or matchState.Winner then
		elapsedClockTime = 0
		publishState(core, carrier, carrierTeam)
	end
end)
