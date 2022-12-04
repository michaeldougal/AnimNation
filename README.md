<div align="center">
<img src="https://user-images.githubusercontent.com/67706277/205463774-5c513218-9ca9-4b36-8d1d-1c1ac75f4c5a.png" />

Built upon the foundations of Tweentown and SpringCity, AnimNation is a utility that makes Roblox object animation using springs and tweens simple and quick.
</div>

<br/>

## Types
### SpringInfo
A dictionary of spring properties such as `{s = 10, d = 0.5}`. Can be constructed using any keys that you could use to create a Spring object. Possible keys:
```lua
Initial = Initial | i
Speed = Speed | s
Damper = Damper | d
Target = Target | t
Velocity = Velocity | v
Position = Position | Value | p
Clock = Clock
```

### AnimChain
An object that listens for the end of a tween/spring animation and then fires any connected `:AndThen()` callbacks. `:AndThen()` always returns the same `AnimChain` object, so you can chain as many callbacks together as you want.

### TweenInfo
`TweenInfo` can be passed to the tweening functions as either a `TweenInfo` object or a dictionary of the desired parameters. Keys are either the `TweenInfo` parameter name or shortened versions:
```lua
Time = Time | t
EasingStyle = EasingStyle | Style | s
EasingDirection = EasingDirection | Direction | d
RepeatCount = RepeatCount | Repeat | rc
Reverses = Reverses | Reverse | r
DelayTime = DelayTime | Delay | dt
```

<br/>

## Tweens
AnimNation tweens support all properties that are supported by TweenService, as well as tweening Models by CFrame and tweening NumberSequence/ColorSequence values	(given that the target sequence has the same number of keypoints).

---

```lua
.tween(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, waitToKill: boolean?): AnimChain
```
Asynchronously performs a tween on the given object. Parameters are identical to `TweenService:Create()`, with the addition of `waitToKill`, which will make	the operation synchronous (yielding) if true. `:AndThen()` can be used to link another function that will be called when the tween completes.

---

```lua
.tweenFromAlpha(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, alpha: number, waitToKill: boolean?): AnimChain
```
Asynchronously performs a tween on the given object, starting from the specified alpha percentage. Otherwise identical to `AnimNation.tween`. Currently supports `number`, `Vector2`, `Vector3`, `CFrame`, `Color3`, `UDim2`, `UDim` and any other type that supports scalar multiplication/addition.

**NOTE:** Currently supports tweening Models by CFrame, but does not yet support tweening NumberSequence/ColorSequence values. Using `.getTweenFromInstance()` will also not return a Tween if using this function. This is due to the backend being a custom solution since Roblox doesn't natively support skipping around in Tween objects :)

---

```lua
.getTweenFromInstance(object: Instance): Tween?
```
Returns the last tween played on the given object, or `nil` if none exists.

<br/>

## Springs
AnimNation springs support the following types: `number`, `Vector2`, `Vector3`, `UDim`, `UDim2`, `CFrame`, and `Color3`. These are natively supported by the provided `Spring` class as well.

---

```lua
.impulse(object: Instance, springInfo: SpringInfo, properties: {[string]: any}, waitToKill: boolean?): AnimChain
```
Asynchronously performs a spring impulse on the given object. The optional `waitToKill` flag will make the operation synchronous (yielding) if true. `:AndThen()` can be used on this function's return value to link another function that will be called when the spring completes (reaches epsilon).

---

```lua
.target(object: Instance, springInfo: SpringInfo, properties: {[string]: any}, waitToKill: boolean?)
```
Asynchronously uses a spring to transition the given object's properties to the specified values. The optional `waitToKill` flag will make the operation synchronous (yielding) if true.

**NOTE:** waitToKill currently exhibits undefined behavior when targeting multiple properties and no AnimChain is returned to enable `:AndThen()` behavior. I plan to fix this and add `:AndThen()` support in a future update.

---

```lua
.bind(springs: {Spring}, label: string, callback: (positions: {Springable}, velocities: {Springable}) -> ())
```
Binds a callback function to the given springs' positions and velocities. Can be used to create more complex and constant interactions with spring values than just a quick impulse or target.

---

```lua
.unbind(spring: Spring, label: string)
```
Unbinds the callback associated with the specified label from updates.

---

```lua
.createSpring(springInfo: SpringInfo, name: string?): Spring
```
Creates a new spring with the given properties and maps it to the specified name, if provided. An initial value can be provided in the SpringInfo table. Aliases: `.register()`

---

```lua
.getSpring(name: string): Spring?
```
Returns the spring with the given name. If none exists, it will return `nil` with a warning, or an error depending on the set `ERROR_POLICY`. Aliases: `.inquire()`
