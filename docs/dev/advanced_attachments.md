# Advanced Attachment Systems & Physics

!!! warning "Canonical Reference"
    This page is supplementary for historical/high-fidelity math notes.
    The implementation source of truth is [Implements, Ground Arbitrator, and Plowing](../systems/ground_effectors_and_plowing.md).
    If any detail differs, follow the systems page.

This document defines the high-fidelity hitch model used to couple a tractor and heavy implements with physically stable behavior at high mass ratios.

!!! abstract "Core Philosophy"
     We use a **Newtonian Exact-Force Joint**. Instead of relying on built-in rigid joints (which become unstable at large mass ratios), we compute the force and torque required to synchronize the implement to the tractor target in one physics frame.

## 1. Target & Float Calculation
The tractor computes a desired transform for the implement from the rear hitch socket and the implement hitch point.

### Terrain Following (Mathematical Float)
A downward `RayCast3D` measures terrain distance $d_{hit}$. The vertical target offset is

$$
\Delta y = L_{spring} - d_{hit}
$$

where $L_{spring}$ is the virtual rest length. This creates the visual effect of a hitch that follows terrain contours without introducing hard-constraint jitter.

## 2. Precise Physical Coupling
Attached implements remain active `RigidBody3D` nodes. We use **Option B: Custom Scripted Joint** to emulate a rigid steel coupling while retaining explicit control over stability.

### 1-Frame Arrival Force
To drive the implement origin to the desired target in one physics tick $\Delta t$:

1. **Target velocity**

    $$
    \vec{v}_{target} = \frac{\vec{r}_{target} - \vec{r}_{current}}{\Delta t}
    $$

2. **Required acceleration**

    $$
    \vec{a} = \frac{\vec{v}_{target} - \vec{v}_{current}}{\Delta t}
    $$

3. **Pull force**

    $$
    \vec{F}_{pull} = m_{implement} \cdot \vec{a}
    $$

### Rotational Torque
To align implement orientation $q_{current}$ with socket orientation $q_{target}$:

1. **Quaternion error**

    $$
    q_{err} = q_{target} \cdot q_{current}^{-1}
    $$

2. **Torque command**

    $$
    \vec{\tau} = I_{approx} \cdot \frac{\vec{\omega}_{target} - \vec{\omega}_{current}}{\Delta t}
    $$

## 3. Stability "Cheats" (Feedback Scaling)
To prevent high-frequency oscillation and tractor zigzag under heavy tow load, we scale the reaction terms applied back to the tractor chassis.

### Lateral Force Suppression
**Problem:** Heavy circular tow motion generates large lateral reaction force that can break rear-wheel traction.

**Mitigation:** Remove the tractor-local lateral component from reaction feedback. The tractor still receives longitudinal drag and vertical load transfer.

$$
\vec{F}_{feedback} = (-\vec{F}_{pull}) - \operatorname{proj}_{\hat{x}_{tractor}}(-\vec{F}_{pull})
$$

### Torque Damping
**Problem:** Perfect reciprocal torque coupling injects high-frequency rotational oscillation into the chassis.

**Mitigation:** Apply only 10% of counter-torque to the tractor, approximating dissipation through tire-ground interaction.

$$
\vec{\tau}_{tractor} = -0.1 \cdot \vec{\tau}_{implement}
$$

## 4. Stall Mechanics & Limits
To prevent explosive force spikes when the implement is blocked (for example, while reversing into a rigid obstacle), we enforce a tow-force cap:

$$
\lVert \vec{F}_{pull} \rVert \le 2 \cdot m_{tractor} \cdot g
$$

When blocked, the force saturates at this limit and feeds back as an anchor load to the tractor body, producing a realistic stall response instead of numerical instability.

## 5. Component-Based Extensibility
To allow any vehicle to utilize this robust Newtonian math, the attachment systems have been refactored into modular components. 

- **HitchSocket3D**: Attach this node wherever a vehicle should receive a connection. It holds the Newtonian force integration code and local hitch offsets.
- **Implement3D**: The abstract base logic for a towed device. It specifies physical dimensions, is_lowered, is_active states, and base virtual template functions like _on_lower_changed(). Subclasses like PlowAttachment.gd execute specialized grid deformation tools here without reinventing physics attachment math.
- **Safety Tethers**: The sockets use bound signal parameters correctly disconnecting internal listeners via _func.bind(socket), enabling memory-safe tear-downs.

---
[Return to Plow Dev Log](../dev_log/plow_attachment.md)

