// Launches the gallery and checks named controls, states and actions through Linux AT-SPI.
#include <atspi/atspi.h>
#include <gio/gio.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <deque>
#include <stdexcept>
#include <string>
#include <thread>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
static void settle(){while(g_main_context_pending(nullptr))g_main_context_iteration(nullptr,false);std::this_thread::sleep_for(std::chrono::milliseconds(100));}
static AtspiAccessible *find(const std::string &name){std::deque<AtspiAccessible *> queue;queue.push_back(atspi_get_desktop(0));
    while(!queue.empty()){auto *object=queue.front();queue.pop_front();if(!object)continue;gchar *label=atspi_accessible_get_name(object,nullptr);
        bool match=label && name==label;g_free(label);
        if(match){for(auto *remaining:queue)if(remaining)g_object_unref(remaining);return object;}
        for(int i=0;i<atspi_accessible_get_child_count(object,nullptr);i++)queue.push_back(atspi_accessible_get_child_at_index(object,i,nullptr));
        g_object_unref(object);}
    return nullptr;}
static AtspiAccessible *require(const std::string &name){auto end=std::chrono::steady_clock::now()+std::chrono::seconds(20);
    while(std::chrono::steady_clock::now()<end){settle();auto *node=find(name);if(node)return node;}throw std::runtime_error("Missing AT-SPI control: "+name);}
static void click(const std::string &name){auto *node=require(name);auto *action=atspi_accessible_get_action_iface(node);bool accepted=false;
    if(action)for(int i=0;i<atspi_action_get_n_actions(action,nullptr);i++){auto *label=atspi_action_get_action_name(action,i,nullptr);
        bool match=label && (std::string(label)=="click"||std::string(label)=="press"||std::string(label)=="toggle");g_free(label);
        if(match){accepted=atspi_action_do_action(action,i,nullptr);break;}}
    if(action)g_object_unref(action);g_object_unref(node);if(!accepted)throw std::runtime_error("Native action rejected: "+name);}
static void has_state(const std::string &name,AtspiStateType state){auto end=std::chrono::steady_clock::now()+std::chrono::seconds(10);
    while(std::chrono::steady_clock::now()<end){settle();auto *node=find(name);if(!node)continue;auto *states=atspi_accessible_get_state_set(node);
        bool found=atspi_state_set_contains(states,state);g_object_unref(states);g_object_unref(node);if(found)return;}
    throw std::runtime_error("Native state did not update: "+name);}
static void expect(const std::string &name){auto *node=require(name);g_object_unref(node);}
int main(int argc,char **argv){if(argc!=3){std::fprintf(stderr,"Usage: accessibility-check executable log-file\n");return 2;}
    g_setenv("GSETTINGS_BACKEND","memory",true);
    GError *error=nullptr;auto *bus=g_bus_get_sync(G_BUS_TYPE_SESSION,nullptr,&error);
    if(!bus){std::fprintf(stderr,"%s\n",error->message);g_error_free(error);return 1;}
    for(auto property:{"IsEnabled","ScreenReaderEnabled"}){auto *reply=g_dbus_connection_call_sync(bus,"org.a11y.Bus","/org/a11y/bus","org.freedesktop.DBus.Properties","Set",
        g_variant_new("(ssv)","org.a11y.Status",property,g_variant_new_boolean(true)),nullptr,G_DBUS_CALL_FLAGS_NONE,10000,nullptr,&error);
        if(!reply){std::fprintf(stderr,"%s\n",error->message);g_error_free(error);g_object_unref(bus);return 1;}g_variant_unref(reply);}
    g_object_unref(bus);atspi_init();pid_t child=fork();if(child==0){std::freopen(argv[2],"w",stdout);dup2(fileno(stdout),STDERR_FILENO);execl(argv[1],argv[1],nullptr);_exit(127);}
    int result=0;
    try {
        for(auto name:{"High contrast","Name","Count","Files"}){auto *node=require(name);auto *role=atspi_accessible_get_role_name(node,nullptr);std::printf("%s: %s\n",name,role);g_free(role);g_object_unref(node);}
        if(std::system("xdotool search --sync --name 'V ImGui: widget gallery' windowfocus")!=0)throw std::runtime_error("Could not focus gallery");
        click("Count");expect("Count: 1");click("High contrast");has_state("High contrast",ATSPI_STATE_CHECKED);
        click("200% text");click("Focus last file");has_state("Photo 0999.jpg",ATSPI_STATE_FOCUSED);
        click("Photo 0999.jpg");expect("Selected Photo 0999.jpg");click("Raw ImGui widgets");settle();click("Accessible controls");expect("Files");
        auto *field=require("Name");auto *edit=atspi_accessible_get_editable_text_iface(field);
        if(!edit||!atspi_editable_text_set_text_contents(edit,"A📷éZ",nullptr))throw std::runtime_error("Unicode native edit rejected");g_object_unref(edit);g_object_unref(field);settle();
        field=require("Name");auto *text=atspi_accessible_get_text_iface(field);gchar *value=atspi_text_get_text(text,0,-1,nullptr);
        if(!value||std::string(value)!="A📷éZ")throw std::runtime_error("Unicode text did not round-trip");g_free(value);
        if(!atspi_text_set_selection(text,0,1,2,nullptr))throw std::runtime_error("Native text selection rejected");g_object_unref(text);g_object_unref(field);
        std::puts("PASS: native AT-SPI roles, actions, contrast, text size, virtual list focus and selection, views, Unicode editing and selection");
    }catch(const std::exception &error){std::fprintf(stderr,"%s\n",error.what());result=1;}
    kill(child,SIGTERM);waitpid(child,nullptr,0);atspi_exit();return result;
}
