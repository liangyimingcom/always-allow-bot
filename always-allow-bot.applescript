-- ============================================================
-- AlwaysAllow Bot v6.1 — macOS Auto-Approve for Electron Apps
--
-- 🤖 Automatically clicks "Always Allow" / "Allow" / "Yes" buttons
--    in Electron apps that require repeated permission confirmations.
--
-- V6.1 Fixes:
--   - Fix "every button of entire contents" -1700 error on Electron
--     Reverted to entire contents + class check approach
--   - Remove do shell script for lowercase (use native AppleScript)
--   - Keep V6 features: dynamic freq/multi-window/fuzzy/blacklist/heartbeat
--
-- ⚙️ CONFIGURATION: Change TARGET_APP_NAME below to your app's process name
--    Find it via: ps aux | grep -i "your-app"
--
-- Run: osascript always-allow-bot.applescript
-- Background: nohup osascript always-allow-bot.applescript > /tmp/always_allow_log.txt 2>&1 &
-- Stop: pkill -f always-allow-bot
-- ============================================================

-- ⚙️ CONFIGURE YOUR TARGET APP HERE ⚙️
set TARGET_APP_NAME to "Amazon Quick"
-- Examples: "Cursor", "VS Code", "Claude", "MyApp"
-- Find your app name: ps aux | grep -i "your-app" | grep -v grep


set clickCount to 0
set loopCount to 0
set errorCount to 0
set switchCount to 0
set drainMax to 2
set cooldownSessions to {}
set cooldownExpiry to {}
set cooldownDuration to 60
set lastHeartbeat to (current date)
set lastClickTime to (current date)
set prevClickCount to 0
set idleRounds to 0

set baseDelay to 0.5
set currentDelay to baseDelay

set heartbeatSeconds to 60
set idleHeartbeatSeconds to 600
set deepIdleHeartbeatSeconds to 1800

-- 日志轮转
try
	set logSize to (do shell script "stat -f%z /tmp/always_allow_log.txt 2>/dev/null || echo 0") as integer
	if logSize > 1048576 then
		do shell script "mv /tmp/always_allow_log.txt /tmp/always_allow_log_prev.txt"
	end if
on error
	-- 忽略
end try

log "=== Target App 自动点击 V6.1 启动 ==="
log "策略: 无条件 Always Allow (基于用户行为观察)"
log "优先级: Always Allow* > Always/始终允许 > Allow > Yes > 模糊匹配"
log "修复: entire contents + class check (兼容 Electron)"
log "按 Ctrl+C 停止"
log "================================================"

repeat
	set loopCount to loopCount + 1
	set cycleClicked to false
	set pendingSessionsToSwitch to {}

	try
		tell application "System Events"
			if not (exists process TARGET_APP_NAME) then
				delay 2
			else if (count of every window of process TARGET_APP_NAME) is 0 then
				delay 1
			else
				-- === 侧栏检测 via entire contents ===
				try
					tell process TARGET_APP_NAME
						set allWinElements to entire contents of window 1
						repeat with elem in allWinElements
							try
								set elemClass to class of elem
								if elemClass is menu item then
									set elemVal to ""
									try
										set elemVal to value of elem as text
									end try
									if elemVal is "" then
										try
											set elemVal to name of elem as text
										end try
									end if
									if elemVal contains "Awaiting approval" or elemVal contains "等待批准" then
										set end of pendingSessionsToSwitch to elem
									end if
								end if
							end try
						end repeat
					end tell
				on error
					-- 侧栏检测失败
				end try

				-- === 清理过期冷却 ===
				set newCooldownSessions to {}
				set newCooldownExpiry to {}
				repeat with i from 1 to (count of cooldownSessions)
					if (item i of cooldownExpiry) > loopCount then
						set end of newCooldownSessions to item i of cooldownSessions
						set end of newCooldownExpiry to item i of cooldownExpiry
					end if
				end repeat
				set cooldownSessions to newCooldownSessions
				set cooldownExpiry to newCooldownExpiry

				-- === 后台 session: 切换 + drain loop ===
				if (count of pendingSessionsToSwitch) > 0 then
					repeat with pendingSession in pendingSessionsToSwitch
						try
							set sessionName to "unknown"
							tell process TARGET_APP_NAME
								try
									set sessionName to value of pendingSession as text
								end try
								if sessionName is "unknown" then
									try
										set sessionName to name of pendingSession as text
									end try
								end if
							end tell

							if sessionName is in cooldownSessions then
								-- 冷却中
							else
								tell process TARGET_APP_NAME
									click pendingSession
								end tell
								set switchCount to switchCount + 1
								log "[" & (time string of (current date)) & "] 切换到: " & sessionName
								delay 1

								-- drain loop
								set drainCount to 0
								repeat drainMax times
									set foundBtn to ""
									tell process TARGET_APP_NAME
										try
											set allElements to entire contents of window 1
											set allowBtn to missing value
											set yesBtn to missing value
											set fuzzyBtn to missing value
											set fuzzyName to ""
											repeat with elem in allElements
												try
													if class of elem is button then
														set btnName to name of elem
														if btnName is missing value then set btnName to ""
														if btnName is not "" then
															set isBlocked to false
															if btnName contains "Reject" or btnName contains "reject" or btnName contains "Deny" or btnName contains "deny" or btnName contains "Cancel" or btnName contains "cancel" or btnName contains "Block" or btnName contains "block" or btnName contains "拒绝" or btnName contains "取消" then
																set isBlocked to true
															end if
															if btnName is "No" or btnName is "no" then
																set isBlocked to true
															end if

															if not isBlocked then
																if btnName starts with "Always Allow" then
																	click elem
																	set foundBtn to btnName
																	exit repeat
																else if btnName is "Always" or btnName is "始终允许" or btnName starts with "始终允许" then
																	click elem
																	set foundBtn to btnName
																	exit repeat
																else if btnName starts with "Allow" then
																	set allowBtn to elem
																else if btnName is "Yes" then
																	set yesBtn to elem
																else if btnName contains "always" or btnName contains "Always" or btnName contains "approve" or btnName contains "Approve" then
																	if fuzzyBtn is missing value then
																		set fuzzyBtn to elem
																		set fuzzyName to btnName
																	end if
																end if
															end if
														end if
													end if
												end try
											end repeat
											if foundBtn is "" then
												if allowBtn is not missing value then
													click allowBtn
													set foundBtn to "Allow (兜底)"
												else if yesBtn is not missing value then
													click yesBtn
													set foundBtn to "Yes (兜底)"
												else if fuzzyBtn is not missing value then
													click fuzzyBtn
													set foundBtn to fuzzyName & " (fuzzy)"
												end if
											end if
										end try
									end tell

									if foundBtn is "" then exit repeat
									set clickCount to clickCount + 1
									set drainCount to drainCount + 1
									set cycleClicked to true
									log "[" & (time string of (current date)) & "] #" & clickCount & " 点击(后台): " & foundBtn
									delay 1
								end repeat

								if drainCount > 1 then
									log "[" & (time string of (current date)) & "] drain: " & drainCount & " 个按钮已处理"
								end if

								if drainCount is 0 then
									set end of cooldownSessions to sessionName
									set end of cooldownExpiry to (loopCount + cooldownDuration)
								end if
							end if
						end try
					end repeat
				end if

				-- === 每轮扫描所有窗口的按钮 ===
				tell process TARGET_APP_NAME
					set allWindows to every window
				end tell
				repeat with win in allWindows
					set drainCount to 0
					repeat drainMax times
						set foundBtn to ""
						tell process TARGET_APP_NAME
							try
								set allElements to entire contents of win
								set allowBtn to missing value
								set yesBtn to missing value
								set fuzzyBtn to missing value
								set fuzzyName to ""
								repeat with elem in allElements
									try
										if class of elem is button then
											set btnName to name of elem
											if btnName is missing value then set btnName to ""
											if btnName is not "" then
												set isBlocked to false
												if btnName contains "Reject" or btnName contains "reject" or btnName contains "Deny" or btnName contains "deny" or btnName contains "Cancel" or btnName contains "cancel" or btnName contains "Block" or btnName contains "block" or btnName contains "拒绝" or btnName contains "取消" then
													set isBlocked to true
												end if
												if btnName is "No" or btnName is "no" then
													set isBlocked to true
												end if

												if not isBlocked then
													if btnName starts with "Always Allow" then
														click elem
														set foundBtn to btnName
														exit repeat
													else if btnName is "Always" or btnName is "始终允许" or btnName starts with "始终允许" then
														click elem
														set foundBtn to btnName
														exit repeat
													else if btnName starts with "Allow" then
														set allowBtn to elem
													else if btnName is "Yes" then
														set yesBtn to elem
													else if btnName contains "always" or btnName contains "Always" or btnName contains "approve" or btnName contains "Approve" then
														if fuzzyBtn is missing value then
															set fuzzyBtn to elem
															set fuzzyName to btnName
														end if
													end if
												end if
											end if
										end if
									end try
								end repeat
								if foundBtn is "" then
									if allowBtn is not missing value then
										click allowBtn
										set foundBtn to "Allow (兜底)"
									else if yesBtn is not missing value then
										click yesBtn
										set foundBtn to "Yes (兜底)"
									else if fuzzyBtn is not missing value then
										click fuzzyBtn
										set foundBtn to fuzzyName & " (fuzzy)"
									end if
								end if
							end try
						end tell

						if foundBtn is "" then exit repeat
						set clickCount to clickCount + 1
						set drainCount to drainCount + 1
						set cycleClicked to true
						log "[" & (time string of (current date)) & "] #" & clickCount & " 点击: " & foundBtn
						delay 1
					end repeat

					if drainCount > 1 then
						log "[" & (time string of (current date)) & "] drain: " & drainCount & " 个按钮已处理"
					end if
				end repeat

				-- NotificationCenter
				try
					if exists process "NotificationCenter" then
						tell process "NotificationCenter"
							if (count of every window) > 0 then
								repeat with nw in every window
									try
										set nElements to entire contents of nw
										repeat with nElem in nElements
											try
												if class of nElem is button then
													set nbName to name of nElem
													if nbName is missing value then set nbName to ""
													if nbName starts with "Always Allow" or nbName is "Always" or nbName is "Allow" or nbName is "始终允许" or nbName starts with "始终允许" then
														click nElem
														set clickCount to clickCount + 1
														set cycleClicked to true
														log "[" & (time string of (current date)) & "] #" & clickCount & " 点击(通知): " & nbName
													end if
												end if
											end try
										end repeat
									end try
								end repeat
							end if
						end tell
					end if
				end try
			end if
		end tell

	on error errMsg
		set errorCount to errorCount + 1
		if errorCount ≤ 10 or (errorCount mod 100) is 0 then
			log "[" & (time string of (current date)) & "] 错误 #" & errorCount & ": " & errMsg
		end if
	end try

	-- 动态频率调节
	if cycleClicked then
		set idleRounds to 0
		set currentDelay to baseDelay
		set lastClickTime to (current date)
	else
		set idleRounds to idleRounds + 1
		if idleRounds ≥ 200 then
			set currentDelay to 1
		else if idleRounds ≥ 50 then
			set currentDelay to 1
		else if idleRounds ≥ 10 then
			set currentDelay to 1
		else
			set currentDelay to baseDelay
		end if
	end if

	-- 动态心跳
	set now to (current date)
	set idleSeconds to (now - lastClickTime)
	if idleSeconds > 3600 then
		set effectiveHeartbeat to deepIdleHeartbeatSeconds
	else if idleSeconds > 300 then
		set effectiveHeartbeat to idleHeartbeatSeconds
	else
		set effectiveHeartbeat to heartbeatSeconds
	end if

	set shouldHeartbeat to false
	if (now - lastHeartbeat) ≥ effectiveHeartbeat then
		set shouldHeartbeat to true
	end if
	if clickCount > prevClickCount then
		set shouldHeartbeat to true
		set prevClickCount to clickCount
	end if

	if shouldHeartbeat then
		log "[" & (time string of now) & "] 心跳 | 轮: " & loopCount & " | 点击: " & clickCount & " | 切换: " & switchCount & " | 错误: " & errorCount & " | 频率: " & currentDelay & "s"
		set lastHeartbeat to now
	end if

	delay currentDelay
end repeat
