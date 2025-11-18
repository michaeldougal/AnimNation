<div align="center">
<img src="https://user-images.githubusercontent.com/67706277/205463774-5c513218-9ca9-4b36-8d1d-1c1ac75f4c5a.png" />

A streamlined Roblox animation utility that simplifies the use of springs,
tweens, and splines on object properties. See <a href="/AnimNation/api/">the API section</a> for usage and
technical details.
</div>

<br/>

## Tweens
Tweens support all properties that are supported by TweenService, as well as tweening Models by `CFrame` and tweening `NumberSequence`/`ColorSequence` values (given that the target sequence has the same number of keypoints).

```lua
.tween(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}): AnimChain
.tweenFromAlpha(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, alpha: number): AnimChain
.getTweenFromInstance(object: Instance): Tween?
```

<br/>

---

## Springs
Springs support the following types: `number`, `Vector2`, `Vector3`, `UDim`, `UDim2`, `CFrame`, and `Color3`. These are natively supported by the provided `Spring` class as well.

```lua
.impulse(object: Instance, springInfo: SpringInfo, properties: {[string]: any}): AnimChain
.target(object: Instance, springInfo: SpringInfo, properties: {[string]: any})
.bind(springs: {Spring}, label: string, callback: (positions: {Springable}, velocities: {Springable}) -> ())
.unbind(spring: Spring, label: string)
.createSpring(springInfo: SpringInfo, name: string?): Spring
.getSpring(name: string): Spring?
```

<br/>

---

## Splines
Splines are used in animation for interpolating between a series of points in a smoothed curving fashion.

```lua
.getSpline(name: string): Spline?
.createSpline(controlPoints: {CFrame}, name: string?): Spline
.slerpTweenFromAlpha(object: Instance, tweenInfo: TweenInfo | {}, spline: Spline | {CFrame}, alignment: ("Track" | "Nodes")?, alpha: number?, waitToKill: boolean?): AnimChain
```
