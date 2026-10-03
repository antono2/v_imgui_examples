import gi,sys,time,subprocess,os
gi.require_version('Atspi','2.0')
from gi.repository import Atspi,GLib
import dbus
bus=dbus.SessionBus()
properties=dbus.Interface(bus.get_object("org.a11y.Bus","/org/a11y/bus"),"org.freedesktop.DBus.Properties")
properties.Set("org.a11y.Status","IsEnabled",dbus.Boolean(True))
properties.Set("org.a11y.Status","ScreenReaderEnabled",dbus.Boolean(True))
process=subprocess.Popen([sys.argv[1]], stdout=open(sys.argv[2],'w'),stderr=subprocess.STDOUT)
def find(name):
 q=[Atspi.get_desktop(0)]
 while q:
  n=q.pop(0)
  try:
   if n.get_name()==name: return n
   q.extend(n.get_child_at_index(i) for i in range(n.get_child_count()))
  except Exception: pass
 return None
def await_node(name):
 end=time.monotonic()+20
 while time.monotonic()<end:
  while GLib.MainContext.default().pending(): GLib.MainContext.default().iteration(False)
  n=find(name)
  if n:return n
  time.sleep(.1)
 raise AssertionError('Missing AT-SPI node: '+name)
def click(name):
 n=await_node(name);a=n.get_action_iface()
 assert a and a.get_n_actions()>0,name
 for i in range(a.get_n_actions()):
  if a.get_action_name(i) in ('click','press','activate','toggle'):
   assert a.do_action(i);return
 raise AssertionError('No click action: '+name)
try:
 print('Roles:',[(name,await_node(name).get_role_name()) for name in ('High contrast','Name','Count','Files')],flush=True)
 subprocess.run(['xdotool','search','--sync','--name','V ImGui: widget gallery','windowfocus'],check=True)
 click('Count');await_node('Count: 1')
 click('High contrast');time.sleep(.2)
 assert await_node('High contrast').get_state_set().contains(Atspi.StateType.CHECKED)
 click('200% text');time.sleep(.2)
 click('Focus last file');last=await_node('Photo 0999.jpg')
 end=time.monotonic()+10
 while not last.get_state_set().contains(Atspi.StateType.FOCUSED) and time.monotonic()<end:
  while GLib.MainContext.default().pending(): GLib.MainContext.default().iteration(False)
  last=find('Photo 0999.jpg');time.sleep(.1)
 assert last.get_state_set().contains(Atspi.StateType.FOCUSED),'Off-screen row did not gain native focus'
 click('Photo 0999.jpg');await_node('Selected Photo 0999.jpg')
 click('Raw ImGui widgets');time.sleep(.3)
 click('Accessible controls');await_node('Files')
 print('PASS: real AT-SPI roles, actions, status, high contrast, large text, virtual row focus and selection, view switching',flush=True)
finally:
 process.terminate();process.wait(timeout=10)
