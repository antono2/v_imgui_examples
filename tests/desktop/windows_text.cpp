// Use the native UIA client API for Unicode selection round trips.
#define NOMINMAX
#include <windows.h>
#include <UIAutomation.h>
#include <cstdio>
#include <string>
#include <stdexcept>
template<class T> struct Com {
    T *value=nullptr;
    ~Com(){if(value)value->Release();}
    T **out(){return &value;}
    T *operator->(){return value;}
};
static void check(HRESULT result) {
    if(FAILED(result))throw std::runtime_error("UIA HRESULT "+std::to_string(static_cast<unsigned long>(result)));
}
static std::wstring content(IUIAutomationTextRange *range) {
    BSTR value=nullptr;check(range->GetText(-1,&value));
    std::wstring result(value?value:L"",value?SysStringLen(value):0);SysFreeString(value);return result;
}
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    check(CoInitializeEx(nullptr,COINIT_MULTITHREADED));
    int result=0;
    try {
        HWND window=reinterpret_cast<HWND>(std::stoull(argv[1]));
        Com<IUIAutomation> automation;check(CoCreateInstance(__uuidof(CUIAutomation),nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(automation.out())));
        Com<IUIAutomationElement> root;check(automation->ElementFromHandle(window,root.out()));
        VARIANT name;VariantInit(&name);name.vt=VT_BSTR;name.bstrVal=SysAllocString(L"Name");
        Com<IUIAutomationCondition> condition;check(automation->CreatePropertyCondition(UIA_NamePropertyId,name,condition.out()));VariantClear(&name);
        Com<IUIAutomationElement> field;check(root->FindFirst(TreeScope_Descendants,condition.value,field.out()));
        if(!field.value)throw std::runtime_error("Missing Name text field");
        Com<IUIAutomationTextPattern> text;check(field->GetCurrentPatternAs(UIA_TextPatternId,IID_PPV_ARGS(text.out())));
        Com<IUIAutomationTextRange> document;check(text->get_DocumentRange(document.out()));
        if(content(document.value)!=L"A\xd83d\xdcf7" L"e\x0301Z")throw std::runtime_error("Unicode document text mismatch");
        Com<IUIAutomationTextRange> range;check(document->Clone(range.out()));
        check(range->MoveEndpointByRange(TextPatternRangeEndpoint_End,range.value,TextPatternRangeEndpoint_Start));
        int moved=0;check(range->MoveEndpointByUnit(TextPatternRangeEndpoint_Start,TextUnit_Character,1,&moved));
        check(range->MoveEndpointByUnit(TextPatternRangeEndpoint_End,TextUnit_Character,1,&moved));
        if(content(range.value)!=L"\xd83d\xdcf7")throw std::runtime_error("Unicode moved range mismatch");
        check(range->Select());
        bool matched=false;
        for(int attempt=0;attempt<300&&!matched;++attempt) {
            Com<IUIAutomationTextRangeArray> selection;check(text->GetSelection(selection.out()));
            int count=0;check(selection->get_Length(&count));
            if(count==1){Com<IUIAutomationTextRange> selected;check(selection->GetElement(0,selected.out()));matched=content(selected.value)==L"\xd83d\xdcf7";}
            if(!matched)Sleep(100);
        }
        if(!matched)throw std::runtime_error("Unicode selection did not round-trip");
        std::puts("PASS: native UIA Unicode document, moved range and selected text");
    }catch(const std::exception &error){std::fprintf(stderr,"%s\n",error.what());result=1;}
    CoUninitialize();return result;
}
