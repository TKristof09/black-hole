import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches

PLOT_SIZE = 10
CAMERA_POS = 10
M = 1
NUM_STEPS = 100000
STEP_SIZE = 0.01


def polar_to_cart(r, phi):
    x = r * np.cos(phi)
    y = r * np.sin(phi)

    return (x, y)

def cart_to_polar(x, y):
    r = np.sqrt(x**2 + y**2)
    phi = np.atan2(y, x)

    return (r, phi)

def calc_tetrad_momentum(r, dir):
    """
    Calculate tetrad for camera on the equatorial plane at r distance
    """
    omega = 1.0
    p_t = omega / np.sqrt(1 - 2*M/r)                # p^t = e_(t)^t * p^(t)
    p_r = omega * np.sqrt(1 - 2*M/r) * dir[0]       # p^r = e_(r)^r * n_r
    p_th = omega * (1.0/r) * dir[1]                 # p^theta = e_(theta)^theta * n_theta
    p_ph = omega * (1.0/(r * 1.0)) * dir[2]         # p^phi = e_(phi)^phi * n_phi (sin theta =1 at equator)
    return np.array([p_t, p_r, p_th, p_ph])

def calc_e_l(r, momentum):
    """
    Calculate E and L from the initial conditions based on the tetrad momentum
    """

    e = (1 - 2 * M / r) * momentum[0]
    l = r * r * momentum[3]
    return e, l



def trace_pr(r0, phi0, dir):

    p = calc_tetrad_momentum(r0, dir)
    e, l = calc_e_l(r0, p)

    t = 0
    r = r0
    phi = phi0


    points = []
    prs = []
    print("null check:", (-(1-2*M/r0)*p[0]*p[0] + (1/(1-2*M/r0))*p[1]*p[1] + r0*r0*p[2]*p[2] + r0*r0*p[3]*p[3]))
    for r in np.linspace(2.1, 10.0, 1000):
        prs.append((r, e * e - (1 - 2 * M / r) * l * l / (r * r)))

    return prs

def trace_photon(r0, phi0, dir):

    momentum = calc_tetrad_momentum(r0, dir)
    e, l = calc_e_l(r0, momentum)

    t = 0
    r = r0
    phi = phi0
    pr = -1 * np.sqrt(e * e - (1 - 2 * M / r) * l * l / (r * r))


    points = []
    

    for i in range(NUM_STEPS):
        # print(f"E={e}, L={l},  r={r},  phi={phi},  t={t}")

        dpr = l * l * (r - 3 * M) / (r * r * r * r)

        t += (e * 1 / (1 - 2 * M / r)) * STEP_SIZE
        phi += l / (r * r) * STEP_SIZE
        r += pr * STEP_SIZE
        pr += dpr * STEP_SIZE


        if r <= 2 * M:
            break
        if r >= 2*PLOT_SIZE:
            break

        points.append(polar_to_cart(r, phi))

    return points


bh = patches.Circle((0, 0), 2*M, fill=False)
plt.figure()

plt.gca().add_patch(bh)
plt.axis("equal")
#
r0, phi0 = cart_to_polar(CAMERA_POS, 0)
# for angle in np.linspace(-np.pi/3, np.pi/3, 100):
#     dir = np.array([-np.cos(angle), 0, np.sin(angle)])
#
#     points = trace_photon(r0, phi0, dir)
#
#     xs = [x for (x, _) in points]
#     ys = [y for (_, y) in points]
#     plt.plot(xs, ys)



# Loopty loop
r0, phi0 = cart_to_polar(0, 3*M+0.0001)
# for angle in np.linspace(-np.pi/3, np.pi/3, 100):
angle = np.atan2(3*M+ 0.0001, 0)
dir = np.array([-np.cos(angle), 0, np.sin(angle)])

points = trace_photon(r0, phi0, dir)

xs = [x for (x, _) in points]
ys = [y for (_, y) in points]
plt.plot(xs, ys)





# angle = np.pi / 3
# dir = np.array([-np.cos(angle), 0, np.sin(angle)])
#
# points = trace_photon(r0, phi0, dir)
#
# xs = [x for (x, _) in points]
# ys = [y for (_, y) in points]
# plt.plot(xs, ys)


plt.grid(True)
plt.show()
