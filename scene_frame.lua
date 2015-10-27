--[[--------------------------------------------------------------------
	
	scene_frame_v3.1.1
	基于界面检测实现界面跳转有限状态机的脚本框架
	
	author  ： 文剑木然
	date    :  2015-10-7

-----------------------------------------------------------------------]]

--[[初始化]]--
--调用框架后会自动执行下面的代码块
	
	--界面配置信息
	scene = {}
	
	--所有界面id
	allSceneId = {}

	--存储界面检测接口得到的坐标信息（仅在检测成功时存储）
	addr = {}
	
	--初始化随机种子
	math.randomseed(os.time())
	
	--默认参数初始化
	
	set = {}
	set.screenRotation = 0						--屏幕旋转
	set.defaultFreq = 2							--默认循环检测频率(Hz)
	set.defaultCount = 10						--默认循环检测最大次数
	set.touchDownDuration = 100					--按下时间(ms)
	set.defaultSleepTime = 500					--默认抬起后延迟时间(ms)
	set.clickRandomRegion = 5					--点击随机偏离范围
	set.checkInterval = nil						--单次检测间隔时间(ms)
	set.logPrintControl = false					--日志输出控制(true:输出调试日志; false:不输出调试日志)
	set.selfCheckControl = true					--进行界面自检控制(true:启用界面自检; false:不启用界面自检)

--[[创建新界面]]--
--在添加界面信息前，需先调用此函数创建新界面
function new(id)
	id = tostring(id)
    scene[id] = {}
    scene[id].next = {}
	scene[id].config = {}
    scene[id].config.freq = set.defaultFreq
    scene[id].config.count = set.defaultCount
    table.insert(allSceneId, id)
	return scene[id]
end	

--[[框架执行入口]]--
--参数配置完毕后，执行此函数使框架运作
function run()
	
	--记录所有id
	for id, singleScene in pairs(scene) do
		
		--界面配置参数初始化
		if type(singleScene.next) == "function" then
			singleScene.next = singleScene.next()
		end
        for i = 1, #singleScene.next do
            singleScene.next[i] = tostring(singleScene.next[i])
        end
		if set.selfCheckControl then
			table.insert(singleScene.next, id)
		end
	end	
	
	--设置屏幕旋转
	rotateScreen(set.screenRotation)
	
	--检测所有界面，启动框架运作
	return checkAllScene()
end

--[[界面列表循环检测]]--
--从给定的界面id列表中循环检测界面。
--输出参数
--		next:	界面id列表
--		freq:	循环检测频率
--		count:	循环检测最大次数
--输出参数
--		若检测成功，返回界面id，否则返回nil
function sceneListCheckLoop(next, freq, count)
	
	for i=1, count do
		keepScreen(true)
		for _, nextId in ipairs(next) do
			local x, y
			x, y = sceneCheckInterface(scene[nextId].info)
			if x~=-1 and y~=-1 then
				keepScreen(false)
                addr[nextId] = {x, y}
				logPrint("界面"..nextId.."检测成功, 坐标:("..x..", "..y..")")
				return nextId
			end
			if set.checkInterval~=nil then
				mSleep(set.checkInterval)
			end
		end
		keepScreen(false)
		mSleep(1000/freq)
	end
	return nil
end

--[[界面操作执行接口]]--
--自动执行给定界面操作
--输入参数
--		currentId:	当前界面id
--		act：		要执行的操作(可为table或function)
--输出参数
--		无。利用尾调递归实现界面连续动作
function sceneActionInterface(currentId, act)
	
	if type(act)=="table" then
        click(table.unpack(act))
	elseif type(act)=="function" then
		act()
	end
	logPrint("界面"..currentId.."的操作执行完毕")	
	local nextId = sceneListCheckLoop(scene[currentId].next, scene[currentId].config.freq, scene[currentId].config.count)
	if nextId~=nil then
		return sceneActionInterface(nextId, scene[nextId].act)
	else
		logPrint("界面"..currentId.."的下一界面检测失败，转向所有界面检测")
		return checkAllScene()
	end
end

--[[点击]]--
--点击函数封装
--输入参数
--	x, y:		点击的坐标
--	sleepTime:	点击后延迟时间
function click(x, y, sleepTime)
	
	--默认参数配置
	sleepTime = sleepTime or set.defaultSleepTime
	
	x = x + math.random(-1*set.clickRandomRegion, set.clickRandomRegion) 
	y = y + math.random(-1*set.clickRandomRegion, set.clickRandomRegion)
	touchDown(0, x, y)
	mSleep(set.touchDownDuration)
	touchUp(0)
	logPrint("点击("..x..", "..y..")")	
	mSleep(sleepTime)
end


--[[多点模糊比色]]--
--输入参数
--		info:	坐标、颜色信息
--		accur:	精确度
--
--输出参数
--		首个点的坐标，若失败则返回-1, -1
function multiCompareColorFuzzy(info, accur)
	local x, y = -1, -1
	for i = 1, #info/3 do 
		x, y = findColorInRegionFuzzy(info[3*i], accur, info[3*i-2], info[3*i-1], info[3*i-2], info[3*i-1])
		if x == -1 or y == -1 then
			return -1, -1
		end
	end
	return info[1], info[2]
end

--[[检测所有界面]]--
function checkAllScene()
	logPrint("检测所有界面...")
	local nextId = sceneListCheckLoop(allSceneId, set.defaultFreq, set.defaultCount)
	if nextId~=nil then
		return sceneActionInterface(nextId, scene[nextId].act)
	else
		logPrint("从所有界面中检测界面失败，再次检测所有界面")
		return checkAllScene()
	end
end	

--[[界面检测接口]]--
--封装三种方式：多点模糊比色、多点区域模糊找色、区域模糊找图
--输入参数
--		info:	坐标、颜色、图片位置信息
--		accur:	精确度
--		range:	找图/找色区域
--输出参数
--		坐标，若找图/找色/比色失败则返回-1, -1
function sceneCheckInterface(info)
	
	local x, y = -1, -1
	--判断传入的info类型，并应用不同的方法
	if type(info)=="table" then
		if type(info[1])=="table" then
            if #info[1]%3==1 then
                x, y = findMultiColorInRegionFuzzy(table.unpack(info))
			elseif #info[1]%3==0 then
                x, y = multiCompareColorFuzzy(table.unpack(info))
            end
        elseif type(info[1])=="string" then
            x, y = findImageInterface(table.unpack(info))
		end
    elseif type(info)=="function" then
        x, y = info()
	end
	return x, y	
end	

--[[找图接口]]--
--将几个找图函数进行封装，便于以接口形式调用
--输入参数
--		参数个数=1 -->  全屏找图
--		参数个数=2, 3  -->  全屏模糊找图
--		参数个数=5, 6  -->  区域模糊找图
--输出参数
--		若找到，返回图片左上角像素点的坐标；若没找到，返回-1, -1
function findImageInterface(...)
    local arg = {...}
    local x, y = -1, -1
    if #arg==1 then
        x, y = findImage(table.unpack(arg))
    elseif #arg==2 or #arg==3 then
        x, y = findImageFuzzy(table.unpack(arg))
    elseif #arg==5 or #arg==6 then
        x, y = findImageInRegionFuzzy(table.unpack(arg))
    end
    return x, y
end
--[[日志输出]]--
--用于脚本调试，通过logPrintControl开关控制是否输出调试日志
function logPrint(...)
	local arg = {...}
	if set.logPrintControl==true then
		logDebug(table.unpack(arg))
	end
end