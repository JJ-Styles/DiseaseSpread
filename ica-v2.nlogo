breed [infected infected-person]
breed [uninfected uninfected-person]
breed [passive-infected passive-infected-person]

infected-own [
  projectile-velocity
  height
  sneeze-tick
  cough-tick
  num-droplets
]

uninfected-own [
  immunity
]

passive-infected-own [
  ticks-since-infected
]

globals [
  averages
  centre-patch
  infected-color
  uninfected-color
  passive-infected-color
  random-direction-angle
  direction-change-tick
  person-step-size
  infection-cone-angle
  movement-boundary-lookahead-size
  droplet-infectiousness ; Infectiousness of a droplet is probability that that one droplet would infect.
  gravitational-acceleration
  patch-to-metres
  vit-d-standard-deviation
  base-immunity
  max-cough-interval
  max-sneeze-interval
  average-male-height
  average-female-height
  height-standard-deviation
  max-cough-droplets
  max-sneeze-droplets
  incubation-period
  average-cough-velocity
  average-sneeze-velocity
  droplets-from-talking
]

to setup-globals
  set averages []
  set centre-patch patch (max-pxcor / 2) (max-pycor / 2)
  set infected-color red
  set uninfected-color blue
  set passive-infected-color yellow
  set random-direction-angle 45
  set direction-change-tick 100
  set person-step-size 0.1
  set infection-cone-angle 90
  set movement-boundary-lookahead-size 5
  set gravitational-acceleration 9.81
  set patch-to-metres 2
  set droplet-infectiousness 0.1
  set vit-d-standard-deviation 0.1
  set base-immunity 0.1
  set max-cough-interval 60
  set max-sneeze-interval 169
  set average-male-height 176
  set average-female-height 163
  set height-standard-deviation 5
  set max-cough-droplets 300
  set max-sneeze-droplets 400
  set incubation-period 20
  set average-cough-velocity 5
  set average-sneeze-velocity 4.5
  set droplets-from-talking 50 ; the number of droplets expelled from the mouth when breathing and talking; produces a very low droplet count just infront of them
end

to setup
  clear-all
  setup-globals
  let sun normalise-sunshine-duration

  create-uninfected number-of-uninfected [
    setxy random-xcor random-ycor
    set color uninfected-color
    set shape "person"
    let vit-d-serum abs (random-normal (sun / 2) vit-d-standard-deviation)
    set immunity base-immunity + (vit-d-serum * 0.3) + (random-float 0.4) ; Models deficiency of vitamin D. Randomness accounts for other factors like HIV, smoking
  ]
  create-infected number-of-infected [
    setxy random-xcor random-ycor
    infect self 0
  ]

  reset-ticks
end

; 1 tick = 1 second
; sleep is = to 8 hours
; therefore 1 day = 16 hours
; every 28,800 ticks is a day.
; every 7200 ticks you sneeze.
; every 2618 ticks you cough.
to go
  ask patches [set pcolor black]

  ask passive-infected [
    ifelse ticks-since-infected >= incubation-period
      [infect self ticks]
      [set ticks-since-infected (ticks-since-infected + 1)]
  ]

  ask turtles [
    if (breed = infected) [
      if ticks = sneeze-tick [
        sneeze self
      ]

      if ticks = cough-tick [
        cough self
      ]

      transmit-disease self
      set num-droplets 0
      set projectile-velocity 0
    ]
    move-person self
  ]
  if not any? uninfected [ stop ]
  tick
end

; For the given infected host, transmit the disease to those in the area.
to transmit-disease [host]
  let modifier (normalise-air-temperature + normalise-rainfall + normalise-relative-humidity) / 3

  let patches-in-radius patches in-cone (infection-distance self) infection-cone-angle ; Range between 1 and 7
  let num-patches count patches-in-radius
  if (num-patches = 0) [set num-patches 1]

  let num-droplets-per-patch droplets-from-talking
  if (num-droplets != 0) [set num-droplets-per-patch (num-droplets / num-patches)]

  let infectiousness-per-patch normalise-infectiousness-per-patch (num-droplets-per-patch * droplet-infectiousness)

  ask patches-in-radius [
    set pcolor floor ((infected-color - 4) + infectiousness-per-patch * 4) ; Visualise the cone in which other people can be infected by the given host
    ask uninfected-here [
      let p infectiousness-per-patch * (modifier * 0.9 + 0.1)
      if (p < 0) [
        show num-droplets-per-patch * droplet-infectiousness
      ]
      set averages (lput p averages)
      if (immunity < p) [
        transmit self
      ]
    ]
  ]
end

; Sets the breed of the given target to passively infected.
to transmit [target]
  set breed passive-infected
  set shape "person"
  set color passive-infected-color
  set ticks-since-infected 0
end

; Sets the breed and other various properties of a turtle to be that of an infected person.
to infect [target t]
  set breed infected
  set shape "person"
  set color infected-color
  set height (random-normal (average-male-height + (average-male-height - average-female-height) / 2) height-standard-deviation) / 100
  set sneeze-tick (t + random max-sneeze-interval) ;average person sneezes roughly 4 times a day, a person with tb is more likely to sneeze
  set cough-tick (t + random max-cough-interval) ;average person coughs roughly 11 times a day, a person with tb is more likely to cough
end

; Moves a person forward, randomly changing direction and steering away from the edges.
to move-person [person]
  ask person [
    let distance-to-edge (get-distance-to-edge self)
    let degree-multiplier 0
    if distance-to-edge > 0 [set degree-multiplier 1 / distance-to-edge]

    if ticks mod (1 + random direction-change-tick) = 0
      [set heading heading + (random-exponential random-direction-angle)]

    ifelse (relative-heading self) < 0 ; -ve if should turn left +ve if should turn right
      [set heading (heading - (359 - heading) * degree-multiplier)]
      [set heading (heading + (heading - 1) * degree-multiplier)]

    forward person-step-size
  ]
end

; Reports the value by which the heading, from the centre patch to the given person, has to be rotated.
; This is negative when a turtle should turn left and +ve when the turtle should turn right, when approaching an edge.
to-report relative-heading [person]
  let dir 0
  ask centre-patch
    [ set dir subtract-headings ([heading] of person) (towards person) ]
  report dir
end

; Reports the distance from the given person to the edge of the view, in patches.
to-report get-distance-to-edge [person]
  let d movement-boundary-lookahead-size
  let distance-to-edge 0

  while [d > 0] [
    ask person [
      ifelse patch-ahead d = nobody
        [set distance-to-edge d
         set d 0]
        [set d (d - person-step-size)]
    ]
  ]

  report distance-to-edge
end

to sneeze [person]
  set sneeze-tick (ticks + random max-sneeze-interval)
  set num-droplets (max-sneeze-droplets + random max-sneeze-droplets)
  set projectile-velocity average-sneeze-velocity
end

to cough [person]
  set cough-tick (ticks + random max-cough-interval)
  set num-droplets (max-cough-droplets + random max-cough-droplets)
  set projectile-velocity average-cough-velocity
end

; Reports the distance that the disease travels from the given person.
; Treat diseased droplets as projectiles and calculate the distance
; using projectile motion formulas, taking into account windspeed.
to-report infection-distance [person]
  let h [height] of person
  let v [projectile-velocity] of person

  if v = 0 [report 1]

  let y (2 * h)
  let z  y / gravitational-acceleration
  let x sqrt(z)
  let d (v + (average-windspeed / 6)) * x

  report ceiling (d / patch-to-metres)
end

; Reports the scaled down sunshine hours, a floating-point number between 0 and 1
to-report normalise-sunshine-duration
  let x sunshine-duration - 53 ; 53 - min sunshine
  let y x / (335 - 53) ; 335 - max sunshine
  report y
end

; Essentially the ratio of infected people to uninfected people.
to-report get-infection-rate
  let num-infected count turtles with [breed = infected]
  let num-uninfected count turtles with [breed = uninfected]

  report (num-infected / num-uninfected) * 100
end

to-report normalise-infectiousness-per-patch [x]
  report ((-1 / 900) * ((x - 30) ^ 2) + 1)
end

to-report normalise-air-temperature
  report ((-1 / 25) * ((air-temperature - 5) ^ 2) + 50) / 50
end

to-report normalise-rainfall
  report 1 - (rainfall / 365)
end

to-report normalise-relative-humidity
  report 1 - (relative-humidity / 100)
end

to-report mean-immunity
  let ai 0
  ask uninfected [
    set ai (ai + immunity)
  ]
  report ai / (count uninfected)
end

to-report lowest-immunity
  let li 1.1
  ask uninfected [
    if immunity < li [set li immunity]
  ]
  report li
end

to-report highest-immunity
  let hi -1
  ask uninfected [
    if immunity > hi [set hi immunity]
  ]
  report hi
end

to-report immunity-standard-deviation
  let m mean-immunity
  let immunities [immunity] of uninfected
  let s reduce + (map [i -> (i - m) ^ 2] immunities)
  report sqrt (s / (count uninfected))
end

to-report mean-probs
  report (reduce + averages) / (length averages)
end

to-report probs-standard-deviation
  let m mean-probs
  let s reduce + (map [i -> (i - m) ^ 2] averages)
  report sqrt (s / (length averages))
end
@#$#@#$#@
GRAPHICS-WINDOW
227
10
950
734
-1
-1
13.0
1
10
1
1
1
0
0
0
1
0
54
0
54
1
1
1
ticks
60.0

SLIDER
6
10
218
43
number-of-uninfected
number-of-uninfected
100
3000
1395.0
1
1
NIL
HORIZONTAL

BUTTON
8
289
82
322
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
88
289
155
322
Start
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
7
52
218
85
number-of-infected
number-of-infected
1
10
1.0
1
1
NIL
HORIZONTAL

MONITOR
8
333
68
378
Infected
count infected
17
1
11

MONITOR
72
334
143
379
Uninfected
count uninfected
17
1
11

SLIDER
7
93
219
126
average-windspeed
average-windspeed
0
103
0.0
1
1
m/s
HORIZONTAL

SLIDER
8
133
219
166
air-temperature
air-temperature
0
40
40.0
1
1
°C
HORIZONTAL

SLIDER
8
171
220
204
relative-humidity
relative-humidity
0
100
0.0
1
1
%
HORIZONTAL

SLIDER
9
209
220
242
sunshine-duration
sunshine-duration
53
335
53.0
1
1
Hours
HORIZONTAL

SLIDER
9
247
220
280
rainfall
rainfall
1
365
365.0
1
1
Days
HORIZONTAL

PLOT
966
10
1211
183
Infection Rate
Time
Infection Rate
0.0
10.0
0.0
0.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot get-infection-rate"

MONITOR
12
391
175
436
infectiousness of breathing
normalise-infectiousness-per-patch 2.5
17
1
11

MONITOR
13
444
159
489
modifier
((((normalise-air-temperature + normalise-rainfall + normalise-relative-humidity) / 3)) * 0.9) + 0.1
17
1
11

MONITOR
15
507
99
552
infectiousness
(normalise-infectiousness-per-patch 30) * (((((normalise-air-temperature + normalise-rainfall + normalise-relative-humidity) / 3)) * 0.9) + 0.1)
17
1
11

MONITOR
966
258
1112
303
NIL
mean-immunity
17
1
11

MONITOR
966
312
1112
357
NIL
lowest-immunity
17
1
11

PLOT
1122
205
1608
412
Immunity
Time
Immunity
0.0
0.0
0.0
1.0
true
true
"" ""
PENS
"mean" 1.0 0 -16777216 true "" "plot mean-immunity"
"min" 1.0 0 -7500403 true "" "plot lowest-immunity"
"max" 1.0 0 -2674135 true "" "plot highest-immunity"
"standard-deviation" 1.0 0 -955883 true "" "plot immunity-standard-deviation"

MONITOR
966
367
1112
412
NIL
highest-immunity
17
1
11

MONITOR
966
205
1111
250
NIL
immunity-standard-deviation
17
1
11

MONITOR
147
334
217
379
Passively-Infected
count passive-infected
17
1
11

MONITOR
965
424
1112
469
NIL
mean-probs
17
1
11

PLOT
1123
425
1609
627
Probability
Time
Probability
0.0
0.0
0.0
1.0
true
true
"" ""
PENS
"mean" 1.0 0 -16777216 true "" "plot mean-probs"
"min" 1.0 0 -7500403 true "" "plot min averages"
"max" 1.0 0 -2674135 true "" "plot max averages"
"standard-deviation" 1.0 0 -955883 true "" "plot probs-standard-deviation"

MONITOR
966
477
1113
522
NIL
min averages
17
1
11

MONITOR
966
530
1112
575
NIL
max averages
17
1
11

MONITOR
966
583
1113
628
NIL
probs-standard-deviation
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
