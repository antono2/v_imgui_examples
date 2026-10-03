package io.antono2.vimgui.examples.touch.test;

import android.app.Activity;
import android.app.Instrumentation;
import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Intent;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.MotionEvent;
import android.view.InputDevice;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import java.util.ArrayDeque;
import java.util.function.Supplier;
import java.util.concurrent.atomic.AtomicReference;

/** Exercises the native Android accessibility provider without changing the
 * user's configured accessibility services. Touch coordinates come from the app's list bounds. */
public final class AccessibilitySmoke extends Instrumentation {
    private UiAutomation automation;
    private String lastTree="";

    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }

    private <T> T await(Supplier<T> probe, String message) {
        long deadline=SystemClock.uptimeMillis()+30000;
        do {
            T value=probe.get();
            if (value!=null) return value;
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis()<deadline);
        throw new AssertionError(message+"; "+lastTree);
    }

    private AccessibilityNodeInfo find(String label) {
        ArrayDeque<AccessibilityNodeInfo> queue=new ArrayDeque<>();
        StringBuilder trace=new StringBuilder();
        for (AccessibilityWindowInfo window:automation.getWindows()) {
            AccessibilityNodeInfo root=window.getRoot();
            trace.append("window=").append(window.getId()).append(" package=").append(root==null?"null":root.getPackageName()).append(';');
            if (root!=null && "io.antono2.vimgui.examples.touch".contentEquals(root.getPackageName()==null?"":root.getPackageName())) queue.add(root);
        }
        while (!queue.isEmpty()) {
            AccessibilityNodeInfo node=queue.removeFirst();
            if (trace.length()<4000) trace.append(node.getClassName()).append(':').append(node.getContentDescription()).append(':').append(node.getText()).append(" children=").append(node.getChildCount()).append(';');
            if (label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()) ||
                label.contentEquals(node.getText()==null?"":node.getText())) return node;
            for (int i=0;i<node.getChildCount();++i) {
                AccessibilityNodeInfo child=node.getChild(i);
                if (child!=null) queue.add(child);
            }
        }
        lastTree=trace.toString();
        return null;
    }

    private AccessibilityNodeInfo node(String label) { return await(() -> find(label),"Missing accessible control: "+label); }
    private void click(String label) {
        if (!node(label).performAction(AccessibilityNodeInfo.ACTION_CLICK)) throw new AssertionError("Click rejected: "+label);
    }
    private View inputView(View root) {
        if (root.getClass().getName().equals("io.antono2.imgui.ImGuiInputView")) return root;
        if (root instanceof ViewGroup) {
            ViewGroup group=(ViewGroup)root;
            for (int i=0;i<group.getChildCount();++i) {
                View result=inputView(group.getChildAt(i));
                if (result!=null) return result;
            }
        }
        return null;
    }

    private void drag(float x, float from, float to) {
        long down=SystemClock.uptimeMillis();
        for (int i=0;i<=21;++i) {
            int action=i==0?MotionEvent.ACTION_DOWN:(i==21?MotionEvent.ACTION_UP:MotionEvent.ACTION_MOVE);
            float y=from+(to-from)*Math.min(i,20)/20;
            MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);
            event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            if (!automation.injectInputEvent(event,true)) throw new AssertionError("Touch injection rejected");
            event.recycle();
            SystemClock.sleep(30);
        }
    }

    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            automation=getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
            AccessibilityServiceInfo info=automation.getServiceInfo();
            info.flags|=AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            automation.setServiceInfo(info);
            Activity activity=startActivitySync(new Intent().setClassName("io.antono2.vimgui.examples.touch",
                "io.antono2.vimgui.demo.ImGuiActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            runOnMainSync(() -> activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON));
            for(String label:new String[]{"V ImGui: touch and text","High contrast","Tap counter","Editable text"}) {
                if(!node(label).isImportantForAccessibility())throw new AssertionError("Control skipped by screen readers: "+label);
            }
            if(!node("High contrast").isCheckable())throw new AssertionError("Checkbox role missing");
            click("High contrast");
            await(() -> node("High contrast").isChecked()?Boolean.TRUE:null,"High contrast did not toggle");
            click("Tap counter"); node("Taps: 1");
            AccessibilityNodeInfo.RangeInfo range=node("Next hundred taps").getRangeInfo();
            if(range==null || Math.abs(range.getCurrent()-.01f)>.001f)throw new AssertionError("Progress range did not update");
            Bundle text=new Bundle(); text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"A📷e\u0301Z");
            if(!node("Editable text").performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,text))throw new AssertionError("Set text rejected");
            await(() -> "A📷e\u0301Z".contentEquals(node("Editable text").getText())?Boolean.TRUE:null,"Unicode text damaged");
            Bundle selection=new Bundle();
            selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT,1);
            selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT,3);
            if(!node("Editable text").performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION,selection))throw new AssertionError("Selection rejected");
            await(() -> node("Editable text").getTextSelectionStart()==1 && node("Editable text").getTextSelectionEnd()==3?Boolean.TRUE:null,"Selection did not round-trip");
            click("Copy all text"); node("Copied all text. The clipboard preview is shown below.");
            click("Clear preview"); node("Preview cleared. The system clipboard is unchanged.");
            click("Read clipboard"); node("Read clipboard. The preview is shown below."); node("A📷e\u0301Z");
            click("Larger text"); node("Text size: 1.10x");
            click("Reset text size"); node("Text size: 1.00x");
            // Restore the visible top, then swipe static instructions rather than the scrollbar.
            node("Tap counter").performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.getId());
            automation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);
            SystemClock.sleep(500);
            Rect before=new Rect();node("Tap counter").getBoundsInScreen(before);
            Rect instructions=new Rect();node("Copy uses the entire editable field; no selection is needed. Read displays the clipboard below.").getBoundsInScreen(instructions);
            if(instructions.height()>0 && instructions.top>150) {
                drag(instructions.centerX(),instructions.centerY(),100);
                await(() -> {Rect after=new Rect();node("Tap counter").getBoundsInScreen(after);return after.top<before.top-10?Boolean.TRUE:null;},"Content swipe did not scroll");
            }
            // Resume without losing the borrowed application state.
            automation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME);
            SystemClock.sleep(300);
            getTargetContext().startActivity(new Intent().setClassName("io.antono2.vimgui.examples.touch",
                "io.antono2.vimgui.demo.ImGuiActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            node("Taps: 1");
            if(!"A📷e\u0301Z".contentEquals(node("Editable text").getText()))throw new AssertionError("Resume lost text");
            click("High contrast");
            result.putString("result","PASS: native accessibility roles, actions, progress, Unicode selection, full-field clipboard, text size, content swipe and resume");
            finish(Activity.RESULT_OK,result);
        } catch(Throwable error) {
            result.putString("result","FAIL: "+error.toString());
            finish(Activity.RESULT_CANCELED,result);
        }
    }
}
