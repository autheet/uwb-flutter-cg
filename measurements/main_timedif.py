import pandas as pd
import plotly.express as px
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter
import plotly.express as px

species = ("Vollständige UWB Initiierung", "OOB-Verbindung", "UWB Austausch")
penguin_means = {
    'iPhone': (2.9, 1.92, 1.076),
    'Android': (2.371, 2.279, 0.92),
}

x = np.arange(len(species))  # the label locations
width = 0.25  # the width of the bars
multiplier = 0

fig, ax = plt.subplots(layout='constrained')

for attribute, measurement in penguin_means.items():
    offset = width * multiplier
    rects = ax.bar(x + offset, measurement, width, label=attribute)
    ax.bar_label(rects, padding=3)
    multiplier += 1

ax.set_ylabel('Dauer in Sekunden')
ax.set_title('Zeitmessung der verschiedenen Verbindungen')
ax.set_xticks(x + width, species)
ax.legend(loc='upper left', ncols=3)
ax.set_ylim(0, 4)

plt.show()
