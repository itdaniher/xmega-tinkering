#! /home/it/node_modules/coffee-script/bin/coffee

# use usb, fs, underscore

usb = require("usb")
fs = require("fs")
_ = require("underscore")

# load register addresses from json
x = JSON.parse fs.readFileSync("iox32a4u.json")

# find device
dev = usb.findByIds(0x59e3, 0xf000)
dev.open()

# basic peek/poke for 8/16b registers
bigWrite = (addr, value, c) -> dev.controlTransfer 0xC0, 0x16, value, addr, 0, c
smallWrite = (addr, value, c) -> dev.controlTransfer 0xC0, 0x08, value, addr, 0, c
smallRead = (addr, c) -> dev.controlTransfer 0xC0, 0x09, 0, addr, 1, (e, d) ->
	console.log d, e
	c()
bigRead = (addr, c) -> dev.controlTransfer 0xC0, 0x17, 0, addr, 2, (e, d) ->
	console.log d[1]<<8|d[0]
	c()

# begin timer/counter abstractions

resPWM = (per) ->
	(Math.log per+1 )/ Math.LN2

periodsFromFreq = (freq) ->
	[1/(2*freq), 1/(2*freq)]

periodsFromRegisters = (ccx, per, div) ->
	freq = (32e6 / div) / (per + 1)
	duty = ccx / per
	period = 1 / freq
	onT = period * duty
	offT = period * (1 - duty)
	onT: onT, offT: offT

registersFromPeriods = (onT, offT) ->
	TC_CSEL_DIV = [1,2,4,8,64,256,1024]
	freq = 1 / (onT + offT)
	possibilities = {}
	errors = [1.0]
	for div in TC_CSEL_DIV
		per = Math.round (32e6/div)/freq
		if per > 3
			ccx =  Math.round per * ( onT / (onT+offT) )
			if per < 1<<16 and ccx < 1<<16
				res = periodsFromRegisters ccx, per, div
				error = Math.max Math.abs (onT-res.onT)/onT, Math.abs (offT-res.offT)/offT
				if error < Math.min errors
					console.log "minimum error " + error.toFixed(6) * 100 + "%"
					errors.push error
					possibilities = div:div, per:per, ccx:ccx
	possibilities

# if you get an on time and an off time
if process.argv.length == 4
	settings = registersFromPeriods 1 * process.argv[2], 1 * process.argv[3]

# if you get a frequency

if process.argv.length == 3
	periods = periodsFromFreq 1 * process.argv[2]
	settings = registersFromPeriods periods[0], periods[1]

console.log settings

# a'la dict(zip(ks,vs))
toDict = (ks, vs) ->
	out = {}
	for i in [0..ks.length-1]
		out[ks[i.toString()]] = vs[i]
	return out

# gross-ish kludge to convert target integer divider to a register value
divs = [1,2,4,8,64,256,1024]
regs = ("TC_CLKSEL_DIV#{div}_gc" for div in divs)
divs = toDict divs, regs
settings.div = x[divs[settings.div]]

# awesome callback stack not actually necessary b/c node-usb makes guarentees of sequential endpoint interactions
smallWrite x.PORTC_DIRSET, x.PIN0_bm | x.PIN1_bm, =>
	smallWrite x.TCC0_CTRLA, settings.div, =>
		smallWrite x.TCC0_CTRLB, x.TC0_CCAEN_bm | x.TC_WGMODE_SINGLESLOPE_gc, =>
			bigWrite x.TCC0_PER, settings.per, =>
				bigWrite x.TCC0_CCA, settings.ccx, =>
					bigRead x.TCC0_CNT, process.exit
