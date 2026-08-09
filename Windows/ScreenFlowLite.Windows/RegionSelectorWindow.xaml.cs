using System.Windows;
using System.Windows.Input;
namespace ScreenFlowLite.Windows;
public partial class RegionSelectorWindow : Window
{
    public Rect SelectedRegion { get; private set; }
    public RegionSelectorWindow() { InitializeComponent(); MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); }; }
    private void Confirm_Click(object sender, RoutedEventArgs e) { SelectedRegion = new Rect(Left, Top, ActualWidth, ActualHeight); DialogResult = true; }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; }
}
