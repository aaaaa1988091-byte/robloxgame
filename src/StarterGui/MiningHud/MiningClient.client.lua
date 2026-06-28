local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SocialService = game:GetService("SocialService")

local player = Players.LocalPlayer
if player:GetAttribute("MiningClientInitialized") then
	script:Destroy()
	return
end
player:SetAttribute("MiningClientInitialized", true)

local mouse = player:GetMouse()
local SHOP_PREVIEW_POSITION = Vector3.new(0, 10000, 0)
local SHOP_SLOT_TWEEN = 0.32

local MiningShared = ReplicatedStorage:WaitForChild("MiningShared")
local MiningRemotes = require(MiningShared:WaitForChild("Remotes"))
local sendNotificationEvent = MiningRemotes.wait("SendNotification")
local teleportEvent = MiningRemotes.wait("TeleportToShop")
local shopActionEvent = MiningRemotes.wait("ShopAction")
local miningEvent = MiningRemotes.wait("MiningEvent")
local rewardEmojiEvent = MiningRemotes.wait("RewardEmojiEvent")
local abilityDraftEvent = MiningRemotes.wait("AbilityDraftEvent")
local weatherEvent = MiningRemotes.wait("WeatherEvent")
local potionActionEvent = MiningRemotes.wait("PotionActionEvent")
local questActionEvent = MiningRemotes.wait("QuestActionEvent")
local questStateFunction = MiningRemotes.wait("GetQuestState")
local shopCatalogFunction = MiningRemotes.wait("GetShopCatalog")
local shopStateFunction = MiningRemotes.wait("GetShopState")
local nextWorldRefreshTimeValue = ReplicatedStorage:WaitForChild("NextWorldRefreshTime")

local playerGui = player:WaitForChild("PlayerGui")
local gui = script:FindFirstAncestorOfClass("ScreenGui") or playerGui:FindFirstChild("MiningHud")
if not gui then
	local starterTemplate = StarterGui:FindFirstChild("MiningHud")
	if starterTemplate then
		-- StarterGui normally clones MiningHud into PlayerGui; wait for that clone instead of creating a second copy.
		gui = playerGui:WaitForChild("MiningHud", 10)
		if not gui then
			gui = starterTemplate:Clone()
			gui.Parent = playerGui
		end
	else
		gui = Instance.new("ScreenGui")
		gui.Name = "MiningHud"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
	return corner
end

local function getOrCreateChild(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing, false
	elseif existing then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created, true
end

local TRANSLATIONS = {
	zh = { home = "一鍵回城", invite = "邀請好友", daily = "每日獎勵", robux = "克金商店", potions = "藥水", quests = "任務", close = "關閉" },
	en = { home = "Home", invite = "Invite", daily = "Daily", robux = "Premium", potions = "Potions", quests = "Quests", close = "Close" },
}
local currentLanguage = "zh"
local function tr(key)
	return (TRANSLATIONS[currentLanguage] and TRANSLATIONS[currentLanguage][key]) or TRANSLATIONS.zh[key] or key
end

local modalLockValue = gui:FindFirstChild("OpenModalCount") or Instance.new("IntValue")
modalLockValue.Name = "OpenModalCount"
modalLockValue.Value = 0
modalLockValue.Parent = gui
local modalFrames = {}
local activeModal = nil
local closeShop = nil
local shopIsOpen = false

local function registerModal(frame)
	modalFrames[frame] = true
end

local function tweenGuiOpen(frame, targetPosition)
	frame.Visible = true
	local targetSize = frame.Size
	frame.Size = UDim2.fromOffset(math.max(20, targetSize.X.Offset * 0.86), math.max(20, targetSize.Y.Offset * 0.86))
	frame.Position = targetPosition + UDim2.fromOffset(0, 28)
	TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = targetPosition, Size = targetSize }):Play()
end

local function tweenGuiClose(frame)
	local tween = TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = math.clamp(frame.BackgroundTransparency + 0.2, 0, 1) })
	tween:Play()
	tween.Completed:Connect(function()
		frame.Visible = false
		frame.BackgroundTransparency = math.max(0, frame.BackgroundTransparency - 0.2)
	end)
end

local function closeModal(frame)
	if frame and frame.Visible then
		tweenGuiClose(frame)
	end
	if activeModal == frame then
		activeModal = nil
		modalLockValue.Value = 0
	end
end

local function openModal(frame, targetPosition)
	for other in pairs(modalFrames) do
		if other ~= frame then
			other.Visible = false
		end
	end
	activeModal = frame
	modalLockValue.Value = 1
	tweenGuiOpen(frame, targetPosition)
end

local function makeImageButton(name, text, size, position, parent, color, imageId)
	local button, created = getOrCreateChild(parent, "ImageButton", name)
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color or Color3.fromRGB(46, 60, 88)
	button.Image = imageId or ""
	button.ScaleType = Enum.ScaleType.Slice
	button.SliceCenter = Rect.new(12, 12, 116, 116)
	button.AutoButtonColor = true
	button.Parent = parent
	if created then
		addCorner(button, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 238, 185)
		stroke.Thickness = 2
		stroke.Transparency = 0.15
		stroke.Parent = button
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -10, 1, -8)
		label.Position = UDim2.fromOffset(5, 4)
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.35
		label.TextScaled = true
		label.Parent = button
	end
	local label = button:FindFirstChild("Label")
	if label then
		label.Text = text
	end
	return button
end

local function makeButton(name, text, size, position, parent)
	return makeImageButton(name, text, size, position, parent, Color3.fromRGB(35, 48, 72))
end
local homeButton = makeButton("TeleportHomeButton", tr("home"), UDim2.fromOffset(120, 42), UDim2.fromOffset(16, 160), gui)
homeButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)


local sideMenu = getOrCreateChild(gui, "Frame", "FeatureMenu")
sideMenu.Size = UDim2.fromOffset(132, 276)
sideMenu.Position = UDim2.fromOffset(16, 210)
sideMenu.BackgroundTransparency = 1
sideMenu.Parent = gui
local featurePanels = {}
local refreshQuestPanel = function() end

local function makeFeaturePanel(key, titleText, bodyText)
	local panel, panelCreated = getOrCreateChild(gui, "Frame", key .. "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 240)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(30, 24, 38)
	panel.Visible = false
	panel.Parent = gui
	registerModal(panel)
	if panelCreated then addCorner(panel, 18) end
	local titleLabel = getOrCreateChild(panel, "TextLabel", "Title")
	titleLabel.Size = UDim2.new(1, -20, 0, 46)
	titleLabel.Position = UDim2.fromOffset(10, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = titleText
	titleLabel.TextColor3 = Color3.fromRGB(255, 232, 170)
	titleLabel.TextScaled = true
	titleLabel.Parent = panel
	local body = getOrCreateChild(panel, "TextLabel", "Body")
	body.Size = UDim2.new(1, -34, 1, -70)
	body.Position = UDim2.fromOffset(17, 58)
	body.BackgroundTransparency = 1
	body.TextWrapped = true
	body.TextScaled = true
	body.TextColor3 = Color3.fromRGB(240, 240, 255)
	body.Text = bodyText
	body.Parent = panel
	local close = makeImageButton(key .. "Close", tr("close"), UDim2.fromOffset(96, 34), UDim2.new(1, -106, 1, -42), panel, Color3.fromRGB(135, 55, 55))
	close.MouseButton1Click:Connect(function() closeModal(panel) end)
	featurePanels[key] = panel
end
for index, item in ipairs({
	{ "invite", tr("invite"), "好友邀請\n• 圖片按鈕入口範本\n• 預留邀請成功獎勵欄位\n• 可替換背景圖片與圖示" },
	{ "daily", tr("daily"), "每日獎勵\n• 第 1~7 天簽到格\n• 今日可領取狀態\n• 預留 Claim 按鈕與獎勵圖示" },
	{ "robux", tr("robux"), "克金商店\n• 禮包卡片模板\n• Robux 商品圖片位\n• 購買按鈕使用圖片按鈕樣式" },
	{ "potions", tr("potions"), "藥水背包\n• 力量藥水：提升挖掘力量\n• 幸運藥水：提高寶箱金錢\n• 速度藥水：提高移動速度" },
	{ "quests", tr("quests"), "每日任務\n• 挖倒 10~20 個仙人掌：力量藥水\n• 挖倒 10~20 顆樹：速度藥水\n• 任務重置與領取按鈕模板" },
}) do
	makeFeaturePanel(item[1], item[2], item[3])
	local button = makeButton(item[1] .. "Button", item[2], UDim2.fromOffset(132, 40), UDim2.fromOffset(0, (index - 1) * 46), sideMenu)
	button.MouseButton1Click:Connect(function()
		if closeShop and shopIsOpen then
			closeShop()
		end
		openModal(featurePanels[item[1]], UDim2.fromScale(0.5, 0.5))
		if item[1] == "quests" then
			refreshQuestPanel()
		end
	end)
end

local function setPanelBody(key, text)
	local panel = featurePanels[key]
	local body = panel and panel:FindFirstChild("Body")
	if body then body.Text = text end
	return panel
end

local invitePanel = setPanelBody("invite", "邀請好友一起挖礦\n成功邀請可保留作為後續獎勵入口。")
if invitePanel then
	local inviteButton = makeImageButton("PromptInviteButton", "開啟好友邀請", UDim2.fromOffset(180, 42), UDim2.fromOffset(90, 145), invitePanel, Color3.fromRGB(55, 105, 185))
	inviteButton.MouseButton1Click:Connect(function()
		local canInvite = false
		pcall(function()
			canInvite = SocialService:CanSendGameInviteAsync(player)
		end)
		if canInvite then
			SocialService:PromptGameInvite(player)
		else
			StarterGui:SetCore("SendNotification", { Title = "無法邀請", Text = "目前平台或體驗設定不支援好友邀請。", Duration = 3 })
		end
	end)
end

local potionPanel = setPanelBody("potions", "選擇藥水立即使用：力量提升挖掘、幸運提升寶箱金錢、速度提升移動。")
if potionPanel then
	for index, potion in ipairs({
		{ id = "Strength", text = "力量藥水\n挖掘 +35%" },
		{ id = "Luck", text = "幸運藥水\n寶箱金錢 +50%" },
		{ id = "Speed", text = "速度藥水\n移速 +25%" },
	}) do
		local useButton = makeImageButton("Use" .. potion.id .. "Potion", potion.text, UDim2.fromOffset(104, 76), UDim2.fromOffset(20 + (index - 1) * 112, 130), potionPanel, Color3.fromRGB(84, 78, 150))
		useButton.MouseButton1Click:Connect(function()
			potionActionEvent:FireServer(potion.id)
		end)
	end
end

local robuxPanel = setPanelBody("robux", "商店顯示\n所有商品以圖片按鈕卡片呈現，可在此替換商品圖與價格。")
if robuxPanel then
	for index, product in ipairs({ "新手禮包", "VIP 加速", "超值金幣" }) do
		makeImageButton("PremiumCard" .. index, product .. "\n顯示位", UDim2.fromOffset(104, 76), UDim2.fromOffset(20 + (index - 1) * 112, 130), robuxPanel, Color3.fromRGB(125, 85, 35))
	end
end

local questCards = {}
refreshQuestPanel = function()
	local questPanel = featurePanels["quests"]
	if not questPanel then return end
	local questState = {}
	pcall(function()
		questState = questStateFunction:InvokeServer()
	end)
	local body = questPanel:FindFirstChild("Body")
	if body then
		body.Text = "每日任務會追蹤你挖掉的仙人掌與樹木；完成後可領取藥水。"
	end
	for _, card in ipairs(questCards) do
		card:Destroy()
	end
	table.clear(questCards)
	for index, quest in ipairs(questState or {}) do
		local card = Instance.new("Frame")
		card.Name = "QuestCard_" .. tostring(quest.id)
		card.Size = UDim2.fromOffset(320, 58)
		card.Position = UDim2.fromOffset(20, 102 + (index - 1) * 64)
		card.BackgroundColor3 = Color3.fromRGB(42, 40, 62)
		card.Parent = questPanel
		addCorner(card, 12)
		table.insert(questCards, card)

		local progressText = string.format("%s  %d/%d\n獎勵：%s * 1", quest.displayName or quest.id, quest.progress or 0, quest.target or 0, quest.rewardName or "藥水")
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -116, 1, -8)
		label.Position = UDim2.fromOffset(10, 4)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(245, 245, 255)
		label.Text = progressText
		label.Parent = card

		local done = (quest.progress or 0) >= (quest.target or 1)
		local claimText = quest.claimed and "已領取" or (done and "領取" or "進行中")
		local claim = makeImageButton("Claim" .. tostring(quest.id), claimText, UDim2.fromOffset(88, 40), UDim2.new(1, -98, 0.5, -20), card, done and Color3.fromRGB(45, 130, 75) or Color3.fromRGB(85, 85, 105))
		claim.Active = done and not quest.claimed
		claim.AutoButtonColor = done and not quest.claimed
		claim.MouseButton1Click:Connect(function()
			if done and not quest.claimed then
				questActionEvent:FireServer("Claim", quest.id)
				task.delay(0.25, refreshQuestPanel)
			end
		end)
	end
end

local infoLabel, infoCreated = getOrCreateChild(gui, "TextLabel", "WorldInfo")
if infoCreated then
infoLabel.Size = UDim2.fromOffset(260, 58)
infoLabel.Position = UDim2.fromOffset(16, 16)
infoLabel.BackgroundTransparency = 0.25
infoLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
infoLabel.TextColor3 = Color3.fromRGB(255, 245, 210)
infoLabel.TextWrapped = true
infoLabel.TextScaled = true
infoLabel.Parent = gui
addCorner(infoLabel, 12)
end

local fullBackpackButton = makeButton("FullBackpackReturnButton", "背包已滿！返回商城", UDim2.fromOffset(260, 58), UDim2.new(0.5, -130, 0.52, 0), gui)
fullBackpackButton.BackgroundColor3 = Color3.fromRGB(170, 80, 35)
fullBackpackButton.Visible = false
fullBackpackButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local shopFrame, shopFrameCreated = getOrCreateChild(gui, "Frame", "ShopFrame")
if shopFrameCreated then
	addCorner(shopFrame, 16)
end
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.Size = UDim2.fromOffset(620, 180)
shopFrame.Position = UDim2.new(0.5, 0, 1, -110)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui
registerModal(shopFrame)

local title, titleCreated = getOrCreateChild(shopFrame, "TextLabel", "Title")
title.Text = "礦工棚子商店"
title.Size = UDim2.new(1, -64, 0, 36)
title.Position = UDim2.fromOffset(16, 8)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 235, 190)
title.TextScaled = true
title.Parent = shopFrame

local closeButton = makeButton("CloseButton", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0, 8), shopFrame)
closeButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
closeButton.MouseButton1Click:Connect(function()
	if closeShop then
		closeShop()
	end
end)

local shopCatalog = shopCatalogFunction:InvokeServer()
local shopState = shopStateFunction:InvokeServer()
local selectedShopIndex = 1
local suppressShopOpenUntil = os.clock() + 2.5
local previousCameraType = nil
local previousCameraSubject = nil
local previousCameraCFrame = nil

local localPreviewFolder = Workspace:FindFirstChild("LocalShopPreviewModels")
if not localPreviewFolder then
	localPreviewFolder = Instance.new("Folder")
	localPreviewFolder.Name = "LocalShopPreviewModels"
	localPreviewFolder.Parent = Workspace
end

local function createLocalPreviewModel(item, index)
	local modelData = item.model or {}
	local model = Instance.new("Model")
	model.Name = "LocalPreview_" .. item.id
	model.Parent = localPreviewFolder

	local mainPart
	local function setupPart(part)
		part.Anchored = true
		part.CanCollide = false
		part:SetAttribute("ShopIndex", index)
		part.Parent = model
		return part
	end

	local source = item.sourceName and localPreviewFolder:FindFirstChild(item.sourceName)
	if source then
		local clone = source:Clone()
		clone.Name = "DisplayModel"
		clone.Parent = model
		mainPart = clone:IsA("BasePart") and clone or clone:FindFirstChildWhichIsA("BasePart", true)
		if mainPart then
			model.PrimaryPart = mainPart
			model:PivotTo(CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new((index - 1) * 5, 3, 0)))
		end
	end
	if mainPart then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant:SetAttribute("ShopIndex", index)
			end
		end
	elseif modelData.kind == "pickaxe" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "Handle"
		mainPart.Size = Vector3.new(0.35, 3.2, 0.35)
		mainPart.Material = Enum.Material.Wood
		mainPart.Color = Color3.fromRGB(125, 78, 38)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(25))

		local head = setupPart(Instance.new("Part"))
		head.Name = "Head"
		head.Size = Vector3.new(2.4, 0.35, 0.35)
		head.Material = modelData.material or Enum.Material.Wood
		head.Color = modelData.color or Color3.fromRGB(150, 100, 50)
		head.CFrame = mainPart.CFrame * CFrame.new(0, 1.35, 0)
	elseif modelData.kind == "bomb" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "BombBody"
		mainPart.Shape = Enum.PartType.Ball
		mainPart.Size = Vector3.new(2.2, 2.2, 2.2)
		mainPart.Material = modelData.material or Enum.Material.Slate
		mainPart.Color = modelData.color or Color3.fromRGB(25, 25, 25)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	elseif modelData.kind == "backpack" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "BackpackBody"
		mainPart.Size = Vector3.new(2.2, 2.8, 1.2)
		mainPart.Material = modelData.material or Enum.Material.Fabric
		mainPart.Color = modelData.color or Color3.fromRGB(85, 135, 210)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	else
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "DisplayBlock"
		mainPart.Size = modelData.size or Vector3.new(2, 2, 2)
		mainPart.Material = modelData.material or Enum.Material.Sand
		mainPart.Color = modelData.color or Color3.fromRGB(235, 205, 130)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	end

	model.PrimaryPart = mainPart
	return model
end


local function refreshCatalogAndPreviews()
	shopCatalog = shopCatalogFunction:InvokeServer()
	shopState = shopStateFunction:InvokeServer()
	for _, child in ipairs(localPreviewFolder:GetChildren()) do
		if child.Name:match("^LocalPreview_") then
			child:Destroy()
		end
	end
	for index, item in ipairs(shopCatalog) do
		createLocalPreviewModel(item, index)
	end
	selectedShopIndex = math.clamp(selectedShopIndex, 1, math.max(1, #shopCatalog))
end

refreshCatalogAndPreviews()

local shopDetailLabel, shopDetailCreated = getOrCreateChild(shopFrame, "TextLabel", "ShopDetail")
shopDetailLabel.Size = UDim2.fromOffset(132, 34)
shopDetailLabel.Position = UDim2.fromOffset(472, 12)
shopDetailLabel.BackgroundTransparency = 0.35
shopDetailLabel.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
shopDetailLabel.TextColor3 = Color3.fromRGB(255, 245, 210)
shopDetailLabel.TextScaled = true
shopDetailLabel.Parent = shopFrame
if shopDetailCreated then addCorner(shopDetailLabel, 10) end

local descriptionLabel, descriptionCreated = getOrCreateChild(shopFrame, "TextLabel", "Description")
if descriptionCreated then
	addCorner(descriptionLabel, 12)
end
descriptionLabel.Size = UDim2.new(1, -40, 0, 56)
descriptionLabel.Position = UDim2.fromOffset(20, 48)
descriptionLabel.BackgroundTransparency = 0.25
descriptionLabel.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
descriptionLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
descriptionLabel.TextWrapped = true
descriptionLabel.TextScaled = true
descriptionLabel.Parent = shopFrame

local previousButton = makeButton("PreviousItem", "◀ 上一個", UDim2.fromOffset(120, 46), UDim2.fromOffset(20, 118), shopFrame)
previousButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local buyButton = makeButton("BuySelected", "購買 / 使用", UDim2.fromOffset(320, 46), UDim2.fromOffset(150, 118), shopFrame)
buyButton.BackgroundColor3 = Color3.fromRGB(35, 95, 55)

local nextButton = makeButton("NextItem", "下一個 ▶", UDim2.fromOffset(120, 46), UDim2.fromOffset(480, 118), shopFrame)
nextButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local function getShopWorld()
	return Workspace:FindFirstChild("MiningShopWorld")
end

local shopOpenCount = 0
local shopPreviewScene = Workspace:FindFirstChild("LocalShop3DPurchaseScene")
if not shopPreviewScene then
	shopPreviewScene = Instance.new("Folder")
	shopPreviewScene.Name = "LocalShop3DPurchaseScene"
	shopPreviewScene.Parent = Workspace
end

local slotLayout = {
	previous = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(-7.5, 1.2, 0)), scale = 0.72, platform = Vector3.new(4.8, 0.45, 3.4), transparency = 0.22 },
	current = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 1.45, 0)), scale = 1.12, platform = Vector3.new(6.4, 0.55, 4.4), transparency = 0 },
	next = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(7.5, 1.2, 0)), scale = 0.72, platform = Vector3.new(4.8, 0.45, 3.4), transparency = 0.22 },
	leftOut = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(-15, 0.9, 0)), scale = 0.55, platform = Vector3.new(3.8, 0.35, 2.8), transparency = 1 },
	rightOut = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(15, 0.9, 0)), scale = 0.55, platform = Vector3.new(3.8, 0.35, 2.8), transparency = 1 },
}
local activeDisplays = {}

local function wrapIndex(index)
	if #shopCatalog == 0 then
		return 1
	end
	return ((index - 1) % #shopCatalog) + 1
end

local function clear3DDisplays()
	for _, display in ipairs(activeDisplays) do
		if display.model and display.model.Parent then
			display.model:Destroy()
		end
	end
	table.clear(activeDisplays)
end

local function clonePreviewModel(item)
	local source = localPreviewFolder:FindFirstChild("LocalPreview_" .. item.id)
	local clone = source and source:Clone()
	if not clone then
		return nil
	end
	clone.Name = "3DItem_" .. item.id
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.Transparency = 0
		end
	end
	return clone
end

local function pivotItemAbovePlatform(itemModel, platform)
	if not itemModel then
		return
	end
	local _, size = itemModel:GetBoundingBox()
	itemModel:PivotTo(platform.CFrame * CFrame.new(0, platform.Size.Y / 2 + math.max(size.Y / 2, 0.8) + 0.2, 0) * CFrame.Angles(0, math.rad(25), 0))
end

local function create3DDisplay(index, layoutKey)
	local item = shopCatalog[wrapIndex(index)]
	if not item then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local displayModel = Instance.new("Model")
	displayModel.Name = "Shop3DDisplay_" .. layoutKey .. "_" .. item.id
	displayModel.Parent = shopPreviewScene

	local platform = Instance.new("Part")
	platform.Name = "WoodDisplayPlatform"
	platform.Size = layout.platform
	platform.Material = Enum.Material.WoodPlanks
	platform.Color = Color3.fromRGB(118, 74, 34)
	platform.Anchored = true
	platform.CanCollide = false
	platform.Transparency = layout.transparency
	platform.CFrame = layout.cframe
	platform.Parent = displayModel
	displayModel.PrimaryPart = platform

	local itemModel = clonePreviewModel(item)
	if itemModel then
		itemModel.Parent = displayModel
		pcall(function() itemModel:ScaleTo(layout.scale) end)
		pivotItemAbovePlatform(itemModel, platform)
		for _, descendant in ipairs(itemModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Transparency = layout.transparency
			end
		end
	end

	local display = { model = displayModel, platform = platform, itemModel = itemModel, layoutKey = layoutKey }
	table.insert(activeDisplays, display)
	return display
end

local function tween3DDisplay(display, layoutKey)
	if not display then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local startPivot = display.model:GetPivot()
	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = startPivot
	pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		display.model:PivotTo(pivotValue.Value)
	end)
	local pivotTween = TweenService:Create(pivotValue, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = layout.cframe })
	local sizeTween = TweenService:Create(display.platform, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = layout.platform, Transparency = layout.transparency })
	for _, descendant in ipairs(display.model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= display.platform then
			TweenService:Create(descendant, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = layout.transparency }):Play()
		end
	end
	pivotTween:Play()
	sizeTween:Play()
	pivotTween.Completed:Connect(function()
		pivotValue:Destroy()
		if display.itemModel then
			pcall(function() display.itemModel:ScaleTo(layout.scale) end)
			pivotItemAbovePlatform(display.itemModel, display.platform)
		end
	end)
	return pivotTween
end

local function render3DShop(direction)
	if #shopCatalog == 0 then
		clear3DDisplays()
		return
	end
	if not direction then
		clear3DDisplays()
		create3DDisplay(selectedShopIndex - 1, "previous")
		create3DDisplay(selectedShopIndex, "current")
		create3DDisplay(selectedShopIndex + 1, "next")
		return
	end

	local oldSelected = direction == "next" and wrapIndex(selectedShopIndex - 1) or wrapIndex(selectedShopIndex + 1)
	clear3DDisplays()
	if direction == "next" then
		local leaving = create3DDisplay(oldSelected - 1, "previous")
		local oldCurrent = create3DDisplay(oldSelected, "current")
		local newCurrent = create3DDisplay(selectedShopIndex, "next")
		local entering = create3DDisplay(selectedShopIndex + 1, "rightOut")
		tween3DDisplay(leaving, "leftOut")
		tween3DDisplay(oldCurrent, "previous")
		tween3DDisplay(newCurrent, "current")
		local tween = tween3DDisplay(entering, "next")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				render3DShop(nil)
			end)
		end
	else
		local entering = create3DDisplay(selectedShopIndex - 1, "leftOut")
		local newCurrent = create3DDisplay(selectedShopIndex, "previous")
		local oldCurrent = create3DDisplay(oldSelected, "current")
		local leaving = create3DDisplay(oldSelected + 1, "next")
		tween3DDisplay(entering, "previous")
		tween3DDisplay(newCurrent, "current")
		tween3DDisplay(oldCurrent, "next")
		local tween = tween3DDisplay(leaving, "rightOut")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				render3DShop(nil)
			end)
		end
	end
end

local function setPreviewVisible(index)
	for _, descendant in ipairs(localPreviewFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("ShopIndex") then
			descendant.Transparency = 1
		end
	end
end

local function updateShopSelection(direction)
	local item = shopCatalog[selectedShopIndex]
	if not item then
		return
	end
	title.Text = item.name .. ((item.price and item.price > 0) and ("  $" .. item.price) or "")
	descriptionLabel.Text = item.description
	shopDetailLabel.Text = string.format("%s｜$%s", item.action or "Item", item.price or 0)
	local label = buyButton:FindFirstChild("Label")
	local buttonText = (item.action == "Sell") and "出售沙子" or "購買"
	if item.action == "BuyTool" and (item.item == "拳頭" or (shopState and shopState.ownedTools and shopState.ownedTools[item.item])) then
		buttonText = (shopState.currentPickaxe == item.item) and "已裝備" or "裝備"
	elseif item.action == "BuyBackpack" and shopState and tonumber(item.item) and shopState.maxSand >= tonumber(item.item) then
		buttonText = "已擁有"
	end
	if label then label.Text = buttonText else buyButton.Text = buttonText end
	setPreviewVisible(selectedShopIndex)
	render3DShop(direction)
end

local function focusShopCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not shopIsOpen then
		previousCameraType = camera.CameraType
		previousCameraSubject = camera.CameraSubject
		previousCameraCFrame = camera.CFrame
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(SHOP_PREVIEW_POSITION + Vector3.new(0, 6, 18), SHOP_PREVIEW_POSITION + Vector3.new(0, 2.4, 0))
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = previousCameraSubject or humanoid
	if humanoid and (not previousCameraSubject or previousCameraSubject.Parent == nil) then
		camera.CameraSubject = humanoid
	end
	if previousCameraCFrame then
		camera.CFrame = previousCameraCFrame
	end
end

local function openShop()
	if os.clock() < suppressShopOpenUntil or shopIsOpen then
		return
	end
	shopOpenCount += 1
	refreshCatalogAndPreviews()
	openModal(shopFrame, UDim2.new(0.5, 0, 1, -110))
	focusShopCamera()
	shopIsOpen = true
	selectedShopIndex = 1
	updateShopSelection(nil)
end

closeShop = function()
	if not shopIsOpen and not shopFrame.Visible then
		return
	end
	shopIsOpen = false
	closeModal(shopFrame)
	suppressShopOpenUntil = os.clock() + 2.5
	clear3DDisplays()
	restoreCamera()
end

previousButton.MouseButton1Click:Connect(function()
	selectedShopIndex = ((selectedShopIndex - 2) % #shopCatalog) + 1
	updateShopSelection("previous")
end)

nextButton.MouseButton1Click:Connect(function()
	selectedShopIndex = (selectedShopIndex % #shopCatalog) + 1
	updateShopSelection("next")
end)

buyButton.MouseButton1Click:Connect(function()
	local item = shopCatalog[selectedShopIndex]
	if item then
		shopActionEvent:FireServer(item.id)
		task.delay(0.25, function()
			shopState = shopStateFunction:InvokeServer()
			updateShopSelection(nil)
		end)
	end
end)

updateShopSelection(nil)

local oldPlayerProgress = gui:FindFirstChild("MiningProgress")
if oldPlayerProgress then
	oldPlayerProgress:Destroy()
end

local activeSurfaceProgress = nil

local function clearSurfaceProgress()
	if activeSurfaceProgress then
		activeSurfaceProgress:Destroy()
		activeSurfaceProgress = nil
	end
end

local function darkenColor(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.45)
end

local function lightenColor(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.18)
end

local function showSurfaceProgress(targetPart, percentRemaining)
	clearSurfaceProgress()
	if not targetPart then
		return
	end
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "MiningProgressSurface"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 40
	surfaceGui.LightInfluence = 0
	surfaceGui.Adornee = targetPart
	surfaceGui.Parent = targetPart

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.fromScale(0.72, 0.16)
	back.BackgroundColor3 = darkenColor(targetPart.Color, 0.58)
	back.BackgroundTransparency = 0.15
	back.Parent = surfaceGui
	addCorner(back, 6)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(percentRemaining, 1)
	bar.BackgroundColor3 = lightenColor(targetPart.Color, 0.16)
	bar.Parent = back
	addCorner(bar, 6)
	activeSurfaceProgress = surfaceGui
end

local selectionBox = Instance.new("SelectionBox")
selectionBox.Name = "TargetBlockHighlight"
selectionBox.Color3 = Color3.fromRGB(90, 60, 30)
selectionBox.LineThickness = 0.05
selectionBox.SurfaceTransparency = 1
selectionBox.Parent = gui

local isMining = false
local pendingBombInput = nil
local bombTrajectoryParts = {}
local LONG_PRESS_SECONDS = 0.25
local THROW_ARC_STEPS = 18

local function equippedBombTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("BombCountName") then
		return tool
	end
	return nil
end

local function clearBombTrajectory()
	for _, part in ipairs(bombTrajectoryParts) do
		part:Destroy()
	end
	table.clear(bombTrajectoryParts)
end

local function drawBombTrajectory(targetPart)
	clearBombTrajectory()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not targetPart then
		return
	end
	local startPosition = root.Position + Vector3.new(0, 2, 0)
	local targetPosition = targetPart.Position
	local apexLift = math.clamp((targetPosition - startPosition).Magnitude * 0.12, 3, 9)
	for step = 1, THROW_ARC_STEPS do
		local alpha = step / THROW_ARC_STEPS
		local marker = Instance.new("Part")
		marker.Name = "BombTrajectoryMarker"
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(0.22, 0.22, 0.22)
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 255, 255)
		marker.Transparency = 0.05 + alpha * 0.35
		marker.Anchored = true
		marker.CanCollide = false
		marker.Position = startPosition:Lerp(targetPosition, alpha) + Vector3.new(0, math.sin(math.pi * alpha) * apexLift, 0)
		marker.Parent = Workspace
		table.insert(bombTrajectoryParts, marker)
	end
end

local function getMineableTarget()
	local target = mouse.Target
	local miningFolder = Workspace:FindFirstChild("DynamicMiningWorld")
	if target and miningFolder and target:IsDescendantOf(miningFolder) then
		return target
	end
	return nil
end

local function updateHighlight(target)
	selectionBox.Adornee = target
	if target then
		selectionBox.Color3 = darkenColor(target.Color, 0.5)
	end
end

sendNotificationEvent.OnClientEvent:Connect(function(titleText, message)
	StarterGui:SetCore("SendNotification", {
		Title = titleText,
		Text = message,
		Duration = 3,
	})
end)

player.CharacterAdded:Connect(function()
	suppressShopOpenUntil = os.clock() + 2.5
	closeShop()
end)

nextWorldRefreshTimeValue.Changed:Connect(function()
	suppressShopOpenUntil = os.clock() + 6
	closeShop()
end)

Lighting.FogColor = Color3.fromRGB(225, 202, 158)
Lighting.FogStart = 240
Lighting.FogEnd = 820
Lighting.Ambient = Color3.fromRGB(128, 104, 82)
Lighting.OutdoorAmbient = Color3.fromRGB(165, 132, 96)
Lighting.Brightness = 2.15
Lighting.ClockTime = 16.25
Lighting.ExposureCompensation = -0.08

local shopTouchConnections = {}
local touchingShopZone = false

local function disconnectShopTouchConnections()
	for _, connection in ipairs(shopTouchConnections) do
		connection:Disconnect()
	end
	table.clear(shopTouchConnections)
end

local function connectShopOpenZone()
	disconnectShopTouchConnections()
	local shopWorld = getShopWorld()
	local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
	if not zone then
		return
	end

	table.insert(shopTouchConnections, zone.Touched:Connect(function(hit)
		local character = player.Character
		if character and hit and hit:IsDescendantOf(character) then
			-- Polling loop below is the only place allowed to open the shop; Touched is noisy on Roblox characters.
		end
	end))

	table.insert(shopTouchConnections, zone.TouchEnded:Connect(function(hit)
		local character = player.Character
		if character and hit and hit:IsDescendantOf(character) then
			task.delay(0.15, function()
				local root = character:FindFirstChild("HumanoidRootPart")
				if not root then
					return
				end
				local flatDistance = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude
				local stillInside = flatDistance <= math.max(zone.Size.Y, zone.Size.Z) / 2 + 1
				if not stillInside then
					touchingShopZone = false
					closeShop()
				end
			end)
		end
	end))
end

connectShopOpenZone()
task.spawn(function()
	while true do
		local shopWorld = getShopWorld()
		local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
		if not zone then
			connectShopOpenZone()
		else
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local flatDistance = root and Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude or math.huge
			local inside = flatDistance <= math.max(zone.Size.Y, zone.Size.Z) / 2
			if inside and not touchingShopZone and modalLockValue.Value == 0 and os.clock() >= suppressShopOpenUntil then
				touchingShopZone = true
				openShop()
			elseif not inside and touchingShopZone then
				touchingShopZone = false
				if shopIsOpen then
					closeShop()
				end
			end
		end
		task.wait(0.25)
	end
end)

local function updateInfoPanel()
	local leaderstats = player:FindFirstChild("leaderstats")
	local sand = leaderstats and leaderstats:FindFirstChild("Sand")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	local maxSand = player:FindFirstChild("MaxSand")
	local remaining = math.max(0, nextWorldRefreshTimeValue.Value - os.time())
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	local sandText = sand and maxSand and (sand.Value .. "/" .. maxSand.Value) or "載入中"
	local coinText = coins and coins.Value or 0
	local totalBlocks = leaderstats and leaderstats:FindFirstChild("TotalBlocks")
	infoLabel.Text = string.format("金錢：$%s  背包：%s  總方塊：%s\n世界刷新：%02d:%02d", coinText, sandText, totalBlocks and totalBlocks.Value or 0, minutes, seconds)
	fullBackpackButton.Visible = sand and maxSand and sand.Value >= maxSand.Value
end

task.spawn(function()
	while true do
		updateInfoPanel()
		task.wait(0.5)
	end
end)

local function playMiningSwing()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end
	local originalGrip = tool.Grip
	for step = 1, 6 do
		local angle = math.sin(step / 6 * math.pi) * math.rad(45)
		tool.Grip = originalGrip * CFrame.Angles(-angle, 0, 0)
		task.wait(0.03)
	end
	if tool.Parent == character then
		tool.Grip = originalGrip
	end
end

mouse.Move:Connect(function()
	updateHighlight(getMineableTarget())
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local target = getMineableTarget()
		updateHighlight(target)
		if tool and tool:GetAttribute("BombCountName") then
			pendingBombInput = input
			task.spawn(function()
				task.wait(LONG_PRESS_SECONDS)
				while pendingBombInput == input and equippedBombTool() do
					drawBombTrajectory(getMineableTarget())
					task.wait(0.08)
				end
			end)
		elseif target then
			miningEvent:FireServer(target)
			task.spawn(playMiningSwing)
		end
		if tool and tool:GetAttribute("AutoMine") then
			isMining = true
			task.spawn(function()
				while isMining do
					local autoTarget = getMineableTarget()
					updateHighlight(autoTarget)
					if autoTarget then
						miningEvent:FireServer(autoTarget)
						task.spawn(playMiningSwing)
					end
					task.wait(0.2)
				end
			end)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isMining = false
		if pendingBombInput then
			local target = getMineableTarget()
			if equippedBombTool() and target then
				miningEvent:FireServer(target)
			end
			pendingBombInput = nil
			clearBombTrajectory()
		end
	end
end)

rewardEmojiEvent.OnClientEvent:Connect(function(emoji, amount)
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardEmojiFly"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Position = UDim2.fromScale(0.5, 0.55)
	rewardLabel.Size = UDim2.fromOffset(150, 52)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = string.format("%s +%s", emoji or "🪙", amount or 0)
	rewardLabel.TextScaled = true
	rewardLabel.TextColor3 = Color3.fromRGB(255, 230, 90)
	rewardLabel.TextStrokeTransparency = 0.25
	rewardLabel.Parent = gui

	local targetX = infoLabel.AbsolutePosition.X + infoLabel.AbsoluteSize.X * 0.45
	local targetY = infoLabel.AbsolutePosition.Y + infoLabel.AbsoluteSize.Y * 0.35
	local tween = game:GetService("TweenService"):Create(rewardLabel, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(targetX, targetY),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		rewardLabel:Destroy()
	end)
end)



local abilityFrame = Instance.new("Frame")
abilityFrame.Name = "AbilityDraftFrame"
abilityFrame.AnchorPoint = Vector2.new(0.5, 0.5)
abilityFrame.Size = UDim2.fromOffset(620, 220)
abilityFrame.Position = UDim2.fromScale(0.5, 0.42)
abilityFrame.BackgroundColor3 = Color3.fromRGB(22, 20, 34)
abilityFrame.Visible = false
abilityFrame.Parent = gui
registerModal(abilityFrame)
addCorner(abilityFrame, 18)
local abilityColors = { green = Color3.fromRGB(80, 190, 95), blue = Color3.fromRGB(75, 145, 255), purple = Color3.fromRGB(175, 90, 255), gold = Color3.fromRGB(255, 205, 65), orange = Color3.fromRGB(255, 125, 35) }
local rarityLabels = { green = "綠", blue = "藍", purple = "紫", gold = "金", orange = "橙" }
local currentAbilityChoices = {}

local function showAbilityDraft(choices, reason)
	currentAbilityChoices = choices or {}
	for _, child in ipairs(abilityFrame:GetChildren()) do
		if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -20, 0, 42)
	header.Position = UDim2.fromOffset(10, 8)
	header.BackgroundTransparency = 1
	header.Text = (reason == "WorldRefresh") and "土地刷新：重新選擇本輪能力" or "每分鐘能力抽選：選擇一張卡"
	header.TextColor3 = Color3.fromRGB(255,255,255)
	header.TextScaled = true
	header.Parent = abilityFrame
	local close = makeImageButton("AbilityClose", "稍後", UDim2.fromOffset(70, 36), UDim2.new(1, -80, 0, 10), abilityFrame, Color3.fromRGB(130, 55, 55))
	close.MouseButton1Click:Connect(function() closeModal(abilityFrame) end)
	for i, data in ipairs(currentAbilityChoices) do
		local cardText = string.format("[%s] %s\n%s", rarityLabels[data.rarity] or data.rarity or "?", data.name or "能力", data.description or "選擇後立即套用。")
		local card = makeImageButton("AbilityCard" .. i, cardText, UDim2.fromOffset(180, 132), UDim2.fromOffset(30 + (i - 1) * 200, 68), abilityFrame)
		card.BackgroundColor3 = abilityColors[data.rarity] or Color3.fromRGB(80, 190, 95)
		card.MouseButton1Click:Connect(function()
			abilityDraftEvent:FireServer("Select", data.name)
			closeModal(abilityFrame)
		end)
	end
	if #currentAbilityChoices > 0 and modalLockValue.Value == 0 then
		openModal(abilityFrame, UDim2.fromScale(0.5, 0.42))
	end
end

abilityDraftEvent.OnClientEvent:Connect(function(messageType, choices, reason)
	if messageType == "Offer" then
		showAbilityDraft(choices, reason)
	end
end)
weatherEvent.OnClientEvent:Connect(function(weatherName)
	if weatherName == "Thunderstorm" then
		Lighting.ClockTime = 20
		Lighting.Brightness = 0.85
		Lighting.FogEnd = 360
		StarterGui:SetCore("SendNotification", { Title = "雷雨來襲", Text = "落雷會燒焦方塊，偶爾引發隕石衝擊。", Duration = 4 })
	else
		Lighting.ClockTime = 16.25
		Lighting.Brightness = 2.15
		Lighting.FogEnd = 820
	end
end)

miningEvent.OnClientEvent:Connect(function(targetPart, currentHealth, maxHealth)
	if currentHealth <= 0 or maxHealth <= 0 then
		clearSurfaceProgress()
		return
	end
	local percentRemaining = math.clamp(currentHealth / maxHealth, 0, 1)
	showSurfaceProgress(targetPart, percentRemaining)
end)
