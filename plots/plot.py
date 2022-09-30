import numpy as np
import matplotlib.pyplot as plt

xlabels = ['1-element array', '64-element array', '256-element array']
ylabel = 'Time for 1M runs (ms)'
xticks = ['0-byte struct', '64-byte struct', '256-byte struct']
labels = ['Old Hook', 'Union Trick', 'Weakly Pure']
values = [
                [[13, 13, 15], [10, 15, 20], [9, 10, 12]],
                [[287, 302, 452], [210, 281, 997], [189, 213, 401]],
                [[999, 1102, 2958], [827, 1085, 3997], [778, 974, 2512]]
        ]

num_plots = 3

colors = ['r', 'g', 'b']

plt.figure(figsize=(20, 8))

for plot_index in range(num_plots):
        # set width of bar
        barWidth = 0.3
        plt.subplot(1, 3, plot_index + 1)

        br = [None] * len(labels)
        br[0] = np.arange(len(values[plot_index][0]))

        for i in range(1, len(values[plot_index][0])):
                br[i] = [x + barWidth for x in br[i - 1]]

        # Make the plot
        for i in range(len(values)):
                plt.bar(br[i], values[plot_index][i], color = colors[i],
                        width = barWidth, edgecolor ='grey', label = labels[i])

        # Adding Xticks
        plt.xlabel(xlabels[plot_index], fontweight ='bold', fontsize = 15)
        plt.ylabel(ylabel, fontweight ='bold', fontsize = 15)
        plt.xticks([r + barWidth for r in range(len(values[plot_index][0]))],
                xticks, fontsize = 13)
        plt.yticks(fontsize = 13)

        plt.legend(fontsize = 15)
plt.savefig('plot.png')
