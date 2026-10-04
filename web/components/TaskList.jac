"""A titled card holding a list of task rows."""

import from core.contracts { TaskView }
import from web.components.TaskRow { TaskRow }
import from web.fmt { duration }


def:pub TaskList(
    title: str,
    tasks: list[TaskView],
    emptyText: str,
    onToggle: Callable[[str], None],
    onDelete: Callable[[str], None],
    onBreakdown: Callable[[str], None],
    tone: str = ""
) -> JsxElement {
    minutes = sum([t.estimate_minutes for t in tasks if not t.done]);
    return
        <section className="card">
            <div className="card-head">
                <h2 className="card-title">{title}</h2>
                <div className="row">
                    {(
                        <span className="pill tabular">{duration(minutes)}</span>
                    ) if minutes > 0 else None}
                    <span className={tone or "pill"}>{str(len(tasks))}</span>
                </div>
            </div>
            <div className="card-body flush">
                {(
                    <div className="empty">{emptyText}</div>
                ) if len(tasks) == 0 else (
                    <div className="task-list">
                        {[
                            <TaskRow
                                key={task.id}
                                task={task}
                                onToggle={lambda { onToggle(task.id); }}
                                onDelete={lambda { onDelete(task.id); }}
                                onBreakdown={lambda { onBreakdown(task.id); }}
                            /> for task in tasks
                        ]}
                    </div>
                )}
            </div>
        </section>;
}
