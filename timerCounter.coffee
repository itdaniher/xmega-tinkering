#! /home/it/node_modules/coffee-script/bin/coffee

usb = require("usb")
fs = require("fs")
_ = require("underscore")

x = JSON.parse fs.readFileSync("iox32a4u.json")

dev = usb.findByIds(0x59e3, 0xf000)
dev.open()

bigWrite = (addr, value, c) -> dev.controlTransfer 0xC0, 0x16, value, addr, 0, c
smallWrite = (addr, value, c) -> dev.controlTransfer 0xC0, 0x08, value, addr, 0, c
smallRead = (addr, c) -> dev.controlTransfer 0xC0, 0x09, 0, addr, 1, (e, d) ->
	console.log d, e
	c()
bigRead = (addr, c) -> dev.controlTransfer 0xC0, 0x17, 0, addr, 2, (e, d) ->
	console.log d[1]<<8|d[0]
	c()

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

if process.argv.length == 4
	settings = registersFromPeriods 1 * process.argv[2], 1 * process.argv[3]

if process.argv.length == 3
	periods = periodsFromFreq 1 * process.argv[2]
	settings = registersFromPeriods periods[0], periods[1]

toDict = (ks, vs) ->
	out = {}
	for i in [0..ks.length-1]
		out[ks[i.toString()]] = vs[i]
	return out

divs = [1,2,4,8,64,256,1024]
regs = ("TC_CLKSEL_DIV#{div}_gc" for div in divs)
divs = toDict divs, regs

#console.log settings

settings.div = x[divs[settings.div]]
#console.log settings
#console.log x.PORTC_DIRSET, x.TCC0_CTRLA, x.TCC0_CTRLB, x.TCC0_PER, x.TCC0_CCA
 
smallWrite x.PORTC_DIRSET, x.PIN0_bm | x.PIN1_bm, =>
	smallWrite x.TCC0_CTRLA, settings.div, =>
		smallWrite x.TCC0_CTRLB, x.TC0_CCAEN_bm | x.TC_WGMODE_SINGLESLOPE_gc, =>
			bigWrite x.TCC0_PER, settings.per, =>
				bigWrite x.TCC0_CCA, settings.ccx, =>
					bigRead x.TCC0_CNT, process.exit
